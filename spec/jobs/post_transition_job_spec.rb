# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tasks::PostTransitionJob, type: :job do
  let(:agent) { create(:agent, :with_team) }
  let(:skill) { create(:skill, content: "Post-hook work") }
  let(:task) { create(:task, status: "in_progress", assigned_to_agent: agent) }

  before do
    task.lock_transition!(agent)
  end

  describe "#perform" do
    context "with no post-hooks" do
      it "unlocks the task immediately" do
        described_class.new.perform(task.id, "in_progress", agent.id, "{}")

        task.reload
        expect(task.transition_locked?).to be false
      end
    end

    context "with post-hooks" do
      it "creates a pipeline session for the first hook" do
        hook = create(:task_hook, :post, task: task, skill: skill, on_status: "in_progress")

        expect {
          described_class.new.perform(task.id, "in_progress", agent.id, "{}")
        }.to have_enqueued_job(ChatStreamJob)

        session = Session.last
        expect(session.metadata["type"]).to eq("task_hook_pipeline")
        expect(session.metadata["pipeline"]["phase"]).to eq("post")
        expect(session.metadata["pipeline"]["hook_ids"]).to include(hook.id)
      end

      it "resolves the agent from the task's current assignee" do
        queen_bee = create(:agent, :with_team, name: "Queen Bee")
        system_agent = create(:agent, name: "System Assistant")
        task.update!(assigned_to_agent: queen_bee)
        create(:task_hook, :post, task: task, skill: skill, on_status: "in_progress", agent: nil)

        described_class.new.perform(task.id, "in_progress", system_agent.id, "{}")

        session = Session.last
        expect(session.agent).to eq(queen_bee)
      end

      it "uses the hook's explicit agent and reassigns the task" do
        hook_agent = create(:agent, :with_team, name: "Hook Agent")
        create(:task_hook, :post, task: task, skill: skill, on_status: "in_progress", agent: hook_agent)

        described_class.new.perform(task.id, "in_progress", agent.id, "{}")

        session = Session.last
        expect(session.agent).to eq(hook_agent)

        task.reload
        expect(task.assigned_to_agent).to eq(hook_agent)
      end

      it "picks up a reassignment made during pre-hooks" do
        new_owner = create(:agent, :with_team, name: "New Owner")
        # Simulate pre-hook reassignment
        task.update!(assigned_to_agent: new_owner)
        create(:task_hook, :post, task: task, skill: skill, on_status: "in_progress", agent: nil)

        described_class.new.perform(task.id, "in_progress", agent.id, "{}")

        session = Session.last
        expect(session.agent).to eq(new_owner)
      end
    end

    it "handles missing task gracefully" do
      expect {
        described_class.new.perform(-1, "in_progress", nil, "{}")
      }.not_to raise_error
    end
  end
end
