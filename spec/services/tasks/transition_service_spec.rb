# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::TransitionService do
  let(:agent) { create(:agent) }

  describe ".call" do
    context "happy path without pre-hooks" do
      it "locks the task and enqueues TransitionJob (skipping pre-phase)" do
        task = create(:task, status: "backlog", assigned_to_agent: agent)

        expect {
          result = described_class.call(task: task, new_status: "todo", agent: agent)
          expect(result).to be_success
          expect(result.data[:pipeline]).to be true
          expect(result.data[:has_pre_hooks]).to be false
        }.to have_enqueued_job(Tasks::TransitionJob)

        task.reload
        expect(task.transition_locked?).to be true
      end

      it "logs a transition_requested event" do
        task = create(:task, status: "backlog")

        expect {
          described_class.call(task: task, new_status: "todo", agent: agent)
        }.to change(TaskEvent, :count).by(1)

        event = TaskEvent.last
        expect(event.event_type).to eq("transition_requested")
        expect(event.summary).to include("skip-pre")
      end
    end

    context "with pre-hooks" do
      it "enqueues PreTransitionJob for the full 3-phase pipeline" do
        task = create(:task, status: "todo", assigned_to_agent: agent)
        skill = create(:skill)
        create(:task_hook, :pre, task: task, skill: skill, on_status: "in_progress")

        expect {
          result = described_class.call(task: task, new_status: "in_progress", agent: agent)
          expect(result).to be_success
          expect(result.data[:has_pre_hooks]).to be true
        }.to have_enqueued_job(Tasks::PreTransitionJob)

        # Task should NOT be locked yet — PreTransitionJob does that
        task.reload
        expect(task.transition_locked?).to be false
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

      it "fails when the task is already locked for transition" do
        task = create(:task, status: "todo")
        task.lock_transition!(agent)

        result = described_class.call(task: task, new_status: "in_progress", agent: agent)

        expect(result).not_to be_success
        expect(result.error).to include("currently being transitioned")
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
        task = create(:task, status: "todo", assigned_to_agent: agent)
        create(:task_dependency, task: task, depends_on: blocker)

        result = described_class.call(task: task, new_status: "in_progress", agent: agent)

        expect(result).to be_success
      end

      it "allows backward transitions even with unmet dependencies" do
        blocker = create(:task, status: "todo")
        task = create(:task, status: "in_progress", assigned_to_agent: agent)
        create(:task_dependency, task: task, depends_on: blocker)

        result = described_class.call(task: task, new_status: "backlog", agent: agent)

        expect(result).to be_success
      end
    end
  end
end
