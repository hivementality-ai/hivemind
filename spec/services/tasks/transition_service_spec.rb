# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::TransitionService do
  let(:agent) { create(:agent) }

  describe ".call" do
    context "happy path" do
      it "transitions the task and logs an event" do
        task = create(:task, status: "backlog")

        result = described_class.call(task: task, new_status: "todo", agent: agent)

        expect(result).to be_success
        expect(task.reload.status).to eq("todo")
        expect(result.data[:old_status]).to eq("backlog")

        event = task.task_events.last
        expect(event.event_type).to eq("status_change")
        expect(event.summary).to include("backlog")
        expect(event.summary).to include("todo")
      end

      it "enqueues post-hooks via TaskHookJob" do
        task = create(:task, status: "todo")

        expect {
          described_class.call(task: task, new_status: "in_progress", agent: agent)
        }.to have_enqueued_job(TaskHookJob)
      end
    end

    context "validation" do
      it "fails for invalid status" do
        task = create(:task, status: "backlog")
        result = described_class.call(task: task, new_status: "invalid")

        expect(result).not_to be_success
        expect(result.error).to include("Invalid status")
      end

      it "fails when already in that status" do
        task = create(:task, status: "todo")
        result = described_class.call(task: task, new_status: "todo")

        expect(result).not_to be_success
        expect(result.error).to include("already")
      end
    end

    context "dependency enforcement" do
      it "blocks transition to in_progress when dependencies not met" do
        blocker = create(:task, status: "todo")
        task = create(:task, status: "todo")
        create(:task_dependency, task: task, depends_on: blocker)

        result = described_class.call(task: task, new_status: "in_progress")

        expect(result).not_to be_success
        expect(result.error).to include("Blocked by incomplete dependencies")
      end

      it "allows transition when dependencies are met" do
        blocker = create(:task, :done)
        task = create(:task, status: "todo")
        create(:task_dependency, task: task, depends_on: blocker)

        result = described_class.call(task: task, new_status: "in_progress")

        expect(result).to be_success
        expect(task.reload.status).to eq("in_progress")
      end

      it "allows backward transitions even with unmet dependencies" do
        blocker = create(:task, status: "todo")
        task = create(:task, status: "in_progress")
        create(:task_dependency, task: task, depends_on: blocker)

        result = described_class.call(task: task, new_status: "backlog")

        expect(result).to be_success
      end
    end

    context "parent-child enforcement" do
      it "blocks subtask from moving to in_progress when parent is in backlog" do
        parent = create(:task, status: "backlog")
        child = create(:task, status: "todo", parent: parent)

        result = described_class.call(task: child, new_status: "in_progress")

        expect(result).not_to be_success
        expect(result.error).to include("Parent task")
        expect(result.error).to include("must be at least in_progress")
      end

      it "blocks subtask from moving to in_progress when parent is in todo" do
        parent = create(:task, status: "todo")
        child = create(:task, status: "todo", parent: parent)

        result = described_class.call(task: child, new_status: "in_progress")

        expect(result).not_to be_success
        expect(result.error).to include("Parent task")
      end

      it "allows subtask to move to in_progress when parent is in_progress" do
        parent = create(:task, status: "in_progress")
        child = create(:task, status: "todo", parent: parent)

        result = described_class.call(task: child, new_status: "in_progress")

        expect(result).to be_success
        expect(child.reload.status).to eq("in_progress")
      end

      it "allows subtask to move to done when parent is in_progress" do
        parent = create(:task, status: "in_progress")
        child = create(:task, status: "review", parent: parent)

        result = described_class.call(task: child, new_status: "done")

        expect(result).to be_success
      end

      it "blocks parent from closing when subtasks are incomplete" do
        parent = create(:task, status: "review")
        create(:task, :done, parent: parent)
        incomplete = create(:task, status: "in_progress", parent: parent)

        result = described_class.call(task: parent, new_status: "done")

        expect(result).not_to be_success
        expect(result.error).to include("subtasks still open")
        expect(result.error).to include("##{incomplete.id}")
      end

      it "allows parent to close when all subtasks are done" do
        parent = create(:task, status: "review")
        create(:task, :done, parent: parent)
        create(:task, :done, parent: parent)

        result = described_class.call(task: parent, new_status: "done")

        expect(result).to be_success
      end

      it "allows parent to close when it has no subtasks" do
        parent = create(:task, status: "review")

        result = described_class.call(task: parent, new_status: "done")

        expect(result).to be_success
      end

      it "allows subtask backward transitions regardless of parent status" do
        parent = create(:task, status: "backlog")
        child = create(:task, status: "in_progress", parent: parent)

        result = described_class.call(task: child, new_status: "todo")

        expect(result).to be_success
      end
    end

    context "pre-hooks" do
      it "blocks transition when pre-hook fails" do
        task = create(:task, status: "todo")
        skill = create(:skill)
        create(:task_hook, :pre, task: task, skill: skill, on_status: "in_progress")

        # Pre-hook will fail because there's no agent to execute it
        result = described_class.call(task: task, new_status: "in_progress")

        expect(result).not_to be_success
        expect(result.error).to include("Pre-hook blocked")
      end
    end
  end
end
