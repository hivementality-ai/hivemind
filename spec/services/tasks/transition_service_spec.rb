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
