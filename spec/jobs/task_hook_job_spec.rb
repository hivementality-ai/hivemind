# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskHookJob, type: :job do
  let(:agent) { create(:agent) }
  let(:skill) { create(:skill) }
  let(:task) { create(:task, assigned_to_agent: agent) }

  describe "#perform" do
    it "executes hooks for the given status and trigger" do
      hook = create(:task_hook, :post, task: task, skill: skill, on_status: "done")

      expect(Tasks::HookExecutor).to receive(:call).with(
        hook: hook, task: task, agent: agent, context: {}
      )

      described_class.new.perform(task.id, "done", "post", agent.id, "{}")
    end

    it "skips disabled hooks" do
      create(:task_hook, :post, task: task, skill: skill, on_status: "done", enabled: false)

      expect(Tasks::HookExecutor).not_to receive(:call)

      described_class.new.perform(task.id, "done", "post", agent.id, "{}")
    end

    it "handles missing task gracefully" do
      expect {
        described_class.new.perform(-1, "done", "post", nil, "{}")
      }.not_to raise_error
    end
  end
end
