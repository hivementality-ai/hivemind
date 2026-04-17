# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::ScheduledTasksSerializer do
  describe ".call" do
    let(:agent) { create(:agent, name: "Scheduler Bot") }

    it "includes name, schedule, and agent" do
      task   = create(:scheduled_task, name: "Daily Report", schedule: "0 9 * * *", agent: agent)
      result = described_class.call(scheduled_task: task)

      expect(result["name"]).to eq("Daily Report")
      expect(result["schedule"]).to eq("0 9 * * *")
      expect(result["agent"]).to eq("Scheduler Bot")
    end

    it "includes description when present" do
      task   = create(:scheduled_task, :with_description, agent: agent)
      result = described_class.call(scheduled_task: task)
      expect(result["description"]).to eq("Test task description")
    end

    it "omits description when blank" do
      task   = create(:scheduled_task, description: nil, agent: agent)
      result = described_class.call(scheduled_task: task)
      expect(result).not_to have_key("description")
    end

    it "omits enabled when task is enabled (true is the default)" do
      task   = create(:scheduled_task, enabled: true, agent: agent)
      result = described_class.call(scheduled_task: task)
      expect(result).not_to have_key("enabled")
    end

    it "includes enabled: false when task is disabled" do
      task   = create(:scheduled_task, :disabled, agent: agent)
      result = described_class.call(scheduled_task: task)
      expect(result["enabled"]).to eq(false)
    end

    it "includes params when present" do
      task   = create(:scheduled_task, :with_job_params, agent: agent)
      result = described_class.call(scheduled_task: task)
      expect(result["params"]).to be_a(Hash)
    end

    it "omits params when empty" do
      task   = create(:scheduled_task, params: {}, agent: agent)
      result = described_class.call(scheduled_task: task)
      expect(result).not_to have_key("params")
    end

    it "returns a Hash" do
      task = create(:scheduled_task, agent: agent)
      expect(described_class.call(scheduled_task: task)).to be_a(Hash)
    end

    it "produces output valid against SwarmSchema scheduled_tasks section" do
      task   = create(:scheduled_task, name: "Schema Test", schedule: "0 9 * * *", agent: agent)
      result = described_class.call(scheduled_task: task)

      raw = {
        "swarm_version"   => "1.0",
        "name"            => "Test",
        "scheduled_tasks" => [result]
      }
      validation = Swarms::SwarmSchema.validate(raw)
      expect(validation).to be_valid, validation.errors.inspect
    end
  end
end
