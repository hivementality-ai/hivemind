# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::ScheduledTasksDeployer do
  def build_document(scheduled_tasks: [])
    Swarms::SwarmDocument.new(
      swarm_version:   "1.0",
      name:            "Test Swarm",
      scheduled_tasks: scheduled_tasks
    )
  end

  let!(:agent) { create(:agent, name: "Target Agent") }

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "returns success when document has no scheduled tasks" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns an empty array when no tasks in document" do
      result = described_class.call(document: build_document)
      expect(result.payload[:scheduled_tasks]).to eq([])
    end

    it "returns one DeployResult per task entry" do
      doc = build_document(scheduled_tasks: [
        { "name" => "Task A", "schedule" => "0 9 * * *", "agent" => agent.name },
        { "name" => "Task B", "schedule" => "0 8 * * *", "agent" => agent.name }
      ])
      result = described_class.call(document: doc)
      expect(result.payload[:scheduled_tasks].size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  describe "creating a new scheduled task" do
    it "creates a ScheduledTask record" do
      doc = build_document(scheduled_tasks: [{
        "name"     => "Morning Briefing",
        "schedule" => "0 9 * * *",
        "agent"    => agent.name
      }])
      expect { described_class.call(document: doc) }.to change(ScheduledTask, :count).by(1)
    end

    it "returns action :created" do
      doc    = build_document(scheduled_tasks: [{ "name" => "New Task", "schedule" => "0 9 * * *", "agent" => agent.name }])
      result = described_class.call(document: doc)
      expect(result.payload[:scheduled_tasks].first.action).to eq(:created)
    end

    it "assigns the correct agent" do
      doc    = build_document(scheduled_tasks: [{ "name" => "Assigned Task", "schedule" => "0 9 * * *", "agent" => agent.name }])
      result = described_class.call(document: doc)
      expect(result.payload[:scheduled_tasks].first.record.agent).to eq(agent)
    end

    it "stores description and params" do
      doc = build_document(scheduled_tasks: [{
        "name"        => "Full Task",
        "schedule"    => "0 9 * * *",
        "agent"       => agent.name,
        "description" => "Does important things",
        "params"      => { "key" => "value" }
      }])
      result = described_class.call(document: doc)
      task   = result.payload[:scheduled_tasks].first.record

      expect(task.description).to eq("Does important things")
      expect(task.params).to eq({ "key" => "value" })
    end

    it "defaults enabled to true when absent" do
      doc    = build_document(scheduled_tasks: [{ "name" => "Default Enabled", "schedule" => "0 9 * * *", "agent" => agent.name }])
      result = described_class.call(document: doc)
      expect(result.payload[:scheduled_tasks].first.record.enabled).to be true
    end

    it "respects enabled: false" do
      doc    = build_document(scheduled_tasks: [{ "name" => "Disabled Task", "schedule" => "0 9 * * *", "agent" => agent.name, "enabled" => false }])
      result = described_class.call(document: doc)
      expect(result.payload[:scheduled_tasks].first.record.enabled).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Missing agent
  # ---------------------------------------------------------------------------

  describe "when the referenced agent does not exist" do
    it "returns action :agent_missing" do
      doc    = build_document(scheduled_tasks: [{ "name" => "Orphan Task", "schedule" => "0 9 * * *", "agent" => "Ghost Agent" }])
      result = described_class.call(document: doc)
      expect(result.payload[:scheduled_tasks].first.action).to eq(:agent_missing)
    end

    it "does not create a ScheduledTask record" do
      doc = build_document(scheduled_tasks: [{ "name" => "Orphan Task", "schedule" => "0 9 * * *", "agent" => "Ghost Agent" }])
      expect { described_class.call(document: doc) }.not_to change(ScheduledTask, :count)
    end

    it "still processes other valid entries" do
      doc = build_document(scheduled_tasks: [
        { "name" => "Orphan",    "schedule" => "0 9 * * *", "agent" => "Ghost Agent" },
        { "name" => "Real Task", "schedule" => "0 9 * * *", "agent" => agent.name }
      ])
      result  = described_class.call(document: doc)
      actions = result.payload[:scheduled_tasks].map(&:action)
      expect(actions).to eq([:agent_missing, :created])
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :skip
  # ---------------------------------------------------------------------------

  describe "strategy :skip" do
    it "returns the existing task unchanged" do
      existing = create(:scheduled_task, name: "Dupe Task", schedule: "0 9 * * *", agent: agent)
      doc      = build_document(scheduled_tasks: [{ "name" => "Dupe Task", "schedule" => "0 6 * * *", "agent" => agent.name }])
      result   = described_class.call(document: doc, resolutions: { "Dupe Task" => :skip })

      dr = result.payload[:scheduled_tasks].first
      expect(dr.action).to eq(:skipped)
      expect(dr.record).to eq(existing)
      expect(existing.reload.schedule).to eq("0 9 * * *")
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :overwrite
  # ---------------------------------------------------------------------------

  describe "strategy :overwrite" do
    it "updates the existing task attributes" do
      existing = create(:scheduled_task, name: "Update Me", schedule: "0 9 * * *", agent: agent)
      doc      = build_document(scheduled_tasks: [{ "name" => "Update Me", "schedule" => "0 12 * * *", "agent" => agent.name }])
      result   = described_class.call(document: doc, resolutions: { "Update Me" => :overwrite })

      dr = result.payload[:scheduled_tasks].first
      expect(dr.action).to eq(:updated)
      expect(existing.reload.schedule).to eq("0 12 * * *")
    end
  end

  # ---------------------------------------------------------------------------
  # Strategy: :rename
  # ---------------------------------------------------------------------------

  describe "strategy :rename" do
    it "creates a new task with a suffixed name" do
      create(:scheduled_task, name: "Report Task", schedule: "0 9 * * *", agent: agent)
      doc    = build_document(scheduled_tasks: [{ "name" => "Report Task", "schedule" => "0 9 * * *", "agent" => agent.name }])
      result = described_class.call(document: doc, resolutions: { "Report Task" => :rename })

      dr = result.payload[:scheduled_tasks].first
      expect(dr.action).to eq(:renamed)
      expect(dr.record.name).to eq("Report Task-2")
    end
  end
  # ---------------------------------------------------------------------------
  # Multi-agent scoping — same task name on different agents must not conflict
  # ---------------------------------------------------------------------------

  describe "agent-scoped conflict detection" do
    let!(:other_agent) { create(:agent, name: "Other Agent") }

    it "does not treat a same-named task on a different agent as a conflict" do
      # 'Morning Briefing' already exists — but owned by other_agent, not agent
      create(:scheduled_task, name: "Morning Briefing", schedule: "0 9 * * *", agent: other_agent)

      doc    = build_document(scheduled_tasks: [{
        "name"     => "Morning Briefing",
        "schedule" => "0 7 * * *",
        "agent"    => agent.name
      }])
      result = described_class.call(document: doc)

      dr = result.payload[:scheduled_tasks].first
      expect(dr.action).to eq(:created)
      expect(dr.record.agent).to eq(agent)
    end

    it "still detects a conflict when the same agent owns the duplicate" do
      create(:scheduled_task, name: "Morning Briefing", schedule: "0 9 * * *", agent: agent)

      doc    = build_document(scheduled_tasks: [{
        "name"     => "Morning Briefing",
        "schedule" => "0 7 * * *",
        "agent"    => agent.name
      }])
      result = described_class.call(document: doc, resolutions: { "Morning Briefing" => :skip })

      dr = result.payload[:scheduled_tasks].first
      expect(dr.action).to eq(:skipped)
    end
  end

end
