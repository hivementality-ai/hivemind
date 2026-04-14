# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::HookExecutor do
  let(:agent) { create(:agent) }
  let(:skill) { create(:skill, content: "Do the thing") }
  let(:task) { create(:task, title: "Test Task", assigned_to_agent: agent) }
  let(:hook) { create(:task_hook, :post, task: task, skill: skill, on_status: "done") }

  describe ".call" do
    it "creates a session and enqueues ChatStreamJob" do
      expect {
        result = described_class.call(hook: hook, task: task, agent: agent)
        expect(result).to be_success
        expect(result.data[:session_id]).to be_present
      }.to have_enqueued_job(ChatStreamJob)
    end

    it "creates a task_event for the hook execution" do
      expect {
        described_class.call(hook: hook, task: task, agent: agent)
      }.to change(TaskEvent, :count).by(1)

      event = TaskEvent.last
      expect(event.event_type).to eq("hook_fired")
      expect(event.summary).to include(skill.name)
    end

    it "creates a session with correct metadata" do
      result = described_class.call(hook: hook, task: task, agent: agent)
      session = Session.find(result.data[:session_id])

      expect(session.metadata["type"]).to eq("task_hook")
      expect(session.metadata["task_id"]).to eq(task.id)
      expect(session.metadata["hook_id"]).to eq(hook.id)
    end

    it "fails when no agent is available" do
      agentless_task = create(:task, assigned_to_agent: nil, created_by_agent: nil)
      agentless_hook = create(:task_hook, :post, task: agentless_task, skill: skill, on_status: "done")

      result = described_class.call(hook: agentless_hook, task: agentless_task)
      expect(result).not_to be_success
      expect(result.error).to include("No agent available")
    end

    it "uses assigned agent from task when no agent passed" do
      result = described_class.call(hook: hook, task: task)
      session = Session.find(result.data[:session_id])

      expect(session.agent).to eq(agent)
    end
  end
end
