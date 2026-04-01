# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::DelegateExecutor do
  let!(:leader) { create(:agent, name: "Leader") }
  let!(:worker) { create(:agent, name: "Worker") }
  let(:session) { create(:session, agent: leader) }

  def build_executor(input)
    described_class.new(input: input, config: { session: session }, agent: leader)
  end

  describe "#call" do
    it "returns failure when no agent name provided" do
      result = build_executor("agent" => "", "task" => "do something").call
      expect(result.success?).to be false
      expect(result.error).to include("No agent name")
    end

    it "returns failure when no task provided" do
      result = build_executor("agent" => "Worker", "task" => "").call
      expect(result.success?).to be false
      expect(result.error).to include("No task")
    end

    it "returns failure when target agent not found" do
      result = build_executor("agent" => "Nobody", "task" => "do something").call
      expect(result.success?).to be false
      expect(result.error).to include("not found")
    end

    it "returns failure when delegating to self" do
      result = build_executor("agent" => "Leader", "task" => "do something").call
      expect(result.success?).to be false
      expect(result.error).to include("Cannot delegate to yourself")
    end

    it "creates a SubAgentTask and enqueues SubAgentJob" do
      expect {
        result = build_executor("agent" => "Worker", "task" => "build the feature").call
        expect(result.success?).to be true
        expect(result.data[:output]).to include("Delegated to Worker")
        expect(result.data[:output]).to include("Task ID:")
        expect(result.data[:output]).to include("delegation_status")
      }.to have_enqueued_job(SubAgentJob)
    end

    it "creates SubAgentTask with correct attributes" do
      build_executor("agent" => "Worker", "task" => "build the feature").call

      sat = SubAgentTask.last
      expect(sat.parent_agent).to eq(leader)
      expect(sat.child_agent).to eq(worker)
      expect(sat.parent_session).to eq(session)
      expect(sat.task).to eq("build the feature")
      expect(sat.status).to eq("pending")
    end

    it "returns immediately without blocking on the delegated agent" do
      expect(Sessions::Chat).not_to receive(:call)

      result = build_executor("agent" => "Worker", "task" => "long running task").call
      expect(result.success?).to be true
    end
  end
end
