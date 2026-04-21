# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::TransitionJob, type: :job do
  let(:agent) { create(:agent, :with_team) }
  let(:task) { create(:task, status: "todo", assigned_to_agent: agent) }

  before do
    task.lock_transition!(agent)
  end

  describe "#perform" do
    it "changes the task status" do
      described_class.new.perform(task.id, "in_progress", agent.id, "{}")

      task.reload
      expect(task.status).to eq("in_progress")
    end

    it "logs a status_change event" do
      expect {
        described_class.new.perform(task.id, "in_progress", agent.id, "{}")
      }.to change(TaskEvent, :count).by_at_least(1)

      event = TaskEvent.where(event_type: "status_change").last
      expect(event.summary).to include("todo")
      expect(event.summary).to include("in_progress")
    end

    it "enqueues PostTransitionJob after the status change" do
      expect {
        described_class.new.perform(task.id, "in_progress", agent.id, "{}")
      }.to have_enqueued_job(Tasks::PostTransitionJob)
    end

    it "keeps the task locked (PostTransitionJob unlocks)" do
      described_class.new.perform(task.id, "in_progress", agent.id, "{}")

      task.reload
      expect(task.transition_locked?).to be true
    end

    context "validation" do
      it "unlocks and skips for invalid status" do
        described_class.new.perform(task.id, "invalid_status", agent.id, "{}")

        task.reload
        expect(task.status).to eq("todo") # unchanged
        expect(task.transition_locked?).to be false
      end

      it "unlocks and skips when already in target status" do
        task.update!(status: "in_progress")

        described_class.new.perform(task.id, "in_progress", agent.id, "{}")

        task.reload
        expect(task.transition_locked?).to be false
      end

      it "skips when task is not locked" do
        task.unlock_transition!

        expect {
          described_class.new.perform(task.id, "in_progress", agent.id, "{}")
        }.not_to have_enqueued_job(Tasks::PostTransitionJob)

        task.reload
        expect(task.status).to eq("todo") # unchanged
      end
    end

    context "dependency enforcement" do
      it "unlocks and skips when blocked by dependencies" do
        blocker = create(:task, status: "todo")
        create(:task_dependency, task: task, depends_on: blocker)

        described_class.new.perform(task.id, "in_progress", agent.id, "{}")

        task.reload
        expect(task.status).to eq("todo") # unchanged
        expect(task.transition_locked?).to be false
      end
    end

    it "handles missing task gracefully" do
      expect {
        described_class.new.perform(-1, "in_progress", nil, "{}")
      }.not_to raise_error
    end
  end
end
