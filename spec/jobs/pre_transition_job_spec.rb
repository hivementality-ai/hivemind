# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::PreTransitionJob, type: :job do
  let(:agent) { create(:agent, :with_team) }
  let(:skill) { create(:skill, content: "Pre-hook work") }
  let(:task) { create(:task, status: "todo", assigned_to_agent: agent) }

  describe "#perform" do
    context "with no pre-hooks" do
      it "locks the task and enqueues TransitionJob directly" do
        expect {
          described_class.new.perform(task.id, "in_progress", agent.id, "{}")
        }.to have_enqueued_job(Tasks::TransitionJob)

        task.reload
        expect(task.transition_locked?).to be true
      end
    end

    context "with pre-hooks" do
      it "locks the task and creates a pipeline session for the first hook" do
        hook = create(:task_hook, :pre, task: task, skill: skill, on_status: "in_progress")

        expect {
          described_class.new.perform(task.id, "in_progress", agent.id, "{}")
        }.to have_enqueued_job(ChatStreamJob)

        task.reload
        expect(task.transition_locked?).to be true

        # Session should carry pipeline metadata
        session = Session.last
        expect(session.metadata["type"]).to eq("task_hook_pipeline")
        expect(session.metadata["pipeline"]["phase"]).to eq("pre")
        expect(session.metadata["pipeline"]["hook_ids"]).to include(hook.id)
      end

      it "resolves the agent from the task's assignee, not the triggering agent" do
        other_agent = create(:agent, :with_team, name: "Queen Bee")
        task.update!(assigned_to_agent: other_agent)
        create(:task_hook, :pre, task: task, skill: skill, on_status: "in_progress", agent: nil)

        described_class.new.perform(task.id, "in_progress", agent.id, "{}")

        session = Session.last
        expect(session.agent).to eq(other_agent)
      end

      it "uses the hook's explicit agent when set" do
        hook_agent = create(:agent, :with_team, name: "Hook Agent")
        create(:task_hook, :pre, task: task, skill: skill, on_status: "in_progress", agent: hook_agent)

        described_class.new.perform(task.id, "in_progress", agent.id, "{}")

        session = Session.last
        expect(session.agent).to eq(hook_agent)

        # Should also reassign the task
        task.reload
        expect(task.assigned_to_agent).to eq(hook_agent)
      end
    end

    context "when task is already locked" do
      it "does not double-lock and does not enqueue TransitionJob" do
        task.lock_transition!(agent)

        expect {
          described_class.new.perform(task.id, "in_progress", agent.id, "{}")
        }.not_to have_enqueued_job(Tasks::TransitionJob)
      end
    end

    it "handles missing task gracefully" do
      expect {
        described_class.new.perform(-1, "in_progress", nil, "{}")
      }.not_to raise_error
    end
  end
end
