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

  describe "prompt enrichment" do
    # We test the prompt content by inspecting what ChatStreamJob receives
    it "includes task description in the prompt" do
      task.update!(description: "Implement the flux capacitor")

      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("Implement the flux capacitor")
        expect(prompt).to include("### Description")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes checklist items in the prompt" do
      task.update!(checklist: [
        { "title" => "Write tests", "checked" => false },
        { "title" => "Update docs", "checked" => true }
      ])

      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("### Checklist")
        expect(prompt).to include("[ ] (index 0) Write tests")
        expect(prompt).to include("[x] (index 1) Update docs")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes comments in the prompt" do
      task.add_comment(author_name: "Doc Brown", body: "Great Scott! Don't forget the 1.21 gigawatts.")

      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("### Comments")
        expect(prompt).to include("Doc Brown")
        expect(prompt).to include("1.21 gigawatts")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes dependency info in the prompt" do
      blocker = create(:task, title: "Build time circuits", status: "in_progress")
      create(:task_dependency, task: task, depends_on: blocker)

      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("### Dependencies")
        expect(prompt).to include("Build time circuits")
        expect(prompt).to include("in_progress")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes downstream tasks in the prompt" do
      downstream = create(:task, title: "Test at 88mph", status: "backlog")
      create(:task_dependency, task: downstream, depends_on: task)

      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("### Downstream Tasks")
        expect(prompt).to include("Test at 88mph")
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end

    it "includes task ID and metadata in the prompt" do
      expect(ChatStreamJob).to receive(:perform_later) do |_session_id, prompt, _files|
        expect(prompt).to include("##{task.id}")
        expect(prompt).to include(task.title)
        expect(prompt).to include(task.priority)
      end

      described_class.call(hook: hook, task: task, agent: agent)
    end
  end
end
