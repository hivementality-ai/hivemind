# frozen_string_literal: true

require "rails_helper"

RSpec.describe Delegations::Request do
  let(:team) { create(:team) }
  let(:from_agent) { create(:agent, team: team) }
  let(:target) { create(:agent, name: "Researcher", team: team) }
  let(:session) { create(:session, agent: from_agent) }

  def request(target_name: target.name, task: "Research the market", from_session: session)
    described_class.call(from_agent: from_agent, from_session: from_session, target_name: target_name, task: task)
  end

  before { allow(SubAgentJob).to receive(:perform_later) }

  describe "happy path" do
    it "creates a SubAgentTask at depth 1 and enqueues the job" do
      result = request

      expect(result).to be_success
      sat = SubAgentTask.find_by(task_key: result.data[:task_key])
      expect(sat.depth).to eq(1)
      expect(sat.child_agent).to eq(target)
      expect(sat.parent_session).to eq(session)
      expect(SubAgentJob).to have_received(:perform_later).with(sat.id)
    end
  end

  describe "input validation" do
    it "rejects a blank target name" do
      expect(request(target_name: "  ").error).to match(/No agent name/)
    end

    it "rejects a blank task" do
      expect(request(task: "").error).to match(/No task/)
    end

    it "rejects self-delegation" do
      result = described_class.call(from_agent: from_agent, from_session: session, target_name: from_agent.name, task: "do it")
      expect(result.error).to match(/yourself/)
    end
  end

  describe "team scoping" do
    it "cannot find an agent on another team" do
      other = create(:agent, name: "Outsider", team: create(:team))
      result = request(target_name: other.name)

      expect(result).not_to be_success
      expect(result.error).to match(/not found/)
    end

    it "a teamless agent keeps the global pool" do
      teamless = create(:agent, team: nil)
      loner_session = create(:session, agent: teamless)
      result = described_class.call(from_agent: teamless, from_session: loner_session, target_name: target.name, task: "help")

      expect(result).to be_success
    end
  end

  describe "spawn-time depth limit" do
    it "rejects delegation from a session at max depth" do
      deep_session = create(:session, agent: from_agent, metadata: { "delegation_depth" => Delegations::Config.max_depth })
      result = request(from_session: deep_session)

      expect(result).not_to be_success
      expect(result.error).to match(/depth limit/)
      expect(SubAgentTask.count).to eq(0)
    end

    it "stamps depth as parent depth + 1" do
      mid_session = create(:session, agent: from_agent, metadata: { "delegation_depth" => 1 })
      result = request(from_session: mid_session)

      expect(SubAgentTask.find_by(task_key: result.data[:task_key]).depth).to eq(2)
    end
  end

  describe "fan-out cap" do
    it "rejects delegation once the active-per-session cap is reached" do
      Delegations::Config.max_concurrent_per_session.times do |i|
        create(:sub_agent_task, parent_session: session, task: "task #{i}", status: "running")
      end

      result = request
      expect(result).not_to be_success
      expect(result.error).to match(/Too many active delegations/)
    end

    it "ignores completed delegations when counting" do
      Delegations::Config.max_concurrent_per_session.times do |i|
        create(:sub_agent_task, :completed, parent_session: session, task: "task #{i}")
      end

      expect(request).to be_success
    end
  end

  describe "duplicate task rejection" do
    it "rejects an identical pending task for the same session" do
      create(:sub_agent_task, parent_session: session, child_agent: target, task: "Research the market")

      result = request
      expect(result).not_to be_success
      expect(result.error).to match(/identical task/)
    end

    it "allows the same task text once the earlier one completed" do
      create(:sub_agent_task, :completed, parent_session: session, child_agent: target, task: "Research the market")

      expect(request).to be_success
    end
  end

  describe "orchestration id and shared budget" do
    it "stamps an orchestration_id on the root session at first delegation" do
      expect(session.metadata&.dig("orchestration_id")).to be_nil

      request
      expect(session.reload.metadata["orchestration_id"]).to be_present
    end

    it "reuses the existing orchestration_id on later delegations" do
      request(task: "first task")
      first_id = session.reload.metadata["orchestration_id"]

      request(task: "second task")
      expect(session.reload.metadata["orchestration_id"]).to eq(first_id)
    end

    it "rejects delegation once the tree's spend crosses the budget" do
      request(task: "seed the orchestration id")
      create(:usage_record, session: session.reload, cost_cents: Delegations::Config.orchestration_budget_cents)

      result = request(task: "one delegation too many")
      expect(result).not_to be_success
      expect(result.error).to match(/Orchestration budget exhausted/)
    end
  end

  describe "configuration via Setting" do
    it "honors a lowered max_depth from the delegation setting" do
      Setting.set("delegation", { "max_depth" => 1 }.to_json)
      mid_session = create(:session, agent: from_agent, metadata: { "delegation_depth" => 1 })

      expect(request(from_session: mid_session).error).to match(/depth limit reached \(1\)/)
    end

    it "clamps settings above the hard ceiling" do
      Setting.set("delegation", { "max_depth" => 50 }.to_json)

      expect(Delegations::Config.max_depth).to eq(Delegations::Config::CEILINGS["max_depth"])
    end

    it "falls back to defaults on malformed JSON" do
      Setting.set("delegation", "not json")

      expect(Delegations::Config.max_depth).to eq(3)
      expect(Delegations::Config.max_concurrent_per_session).to eq(5)
      expect(Delegations::Config.dedup_pending?).to be(true)
    end
  end
end
