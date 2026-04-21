# frozen_string_literal: true

require "rails_helper"

RSpec.describe TaskPipelineContinuation do
  # Test via ChatStreamJob since it includes the concern
  let(:agent) { create(:agent, :with_team) }
  let(:skill) { create(:skill, content: "Do the thing") }
  let(:task) { create(:task, status: "in_progress", assigned_to_agent: agent) }

  # Create a test harness that includes the concern
  let(:harness) do
    Class.new do
      include TaskPipelineContinuation
      # Expose private methods for testing
      public :continue_task_pipeline_if_needed
    end.new
  end

  describe "#continue_task_pipeline_if_needed" do
    context "when session is not a pipeline session" do
      it "does nothing for regular sessions" do
        session = create(:session, agent: agent, metadata: { "type" => "chat" })

        expect { harness.continue_task_pipeline_if_needed(session) }.not_to raise_error
      end

      it "does nothing for nil session" do
        expect { harness.continue_task_pipeline_if_needed(nil) }.not_to raise_error
      end

      it "does nothing for task_hook sessions (non-pipeline)" do
        session = create(:session, agent: agent, metadata: { "type" => "task_hook" })

        expect { harness.continue_task_pipeline_if_needed(session) }.not_to raise_error
      end
    end

    context "pre-phase completion with single hook" do
      it "enqueues TransitionJob when the last pre-hook session completes" do
        hook = create(:task_hook, :pre, task: task, skill: skill, on_status: "in_progress")
        task.lock_transition!(agent)

        pipeline_meta = {
          "task_id" => task.id,
          "new_status" => "in_progress",
          "triggering_agent_id" => agent.id,
          "context_json" => "{}",
          "phase" => "pre",
          "hook_ids" => [hook.id],
          "current_hook_index" => 0
        }

        session = create(:session, agent: agent, metadata: {
          "type" => "task_hook_pipeline",
          "pipeline" => pipeline_meta
        })

        expect {
          harness.continue_task_pipeline_if_needed(session)
        }.to have_enqueued_job(Tasks::TransitionJob).with(task.id, "in_progress", agent.id, "{}")
      end
    end

    context "pre-phase completion with multiple hooks" do
      it "fires next hook session when more pre-hooks remain" do
        hook1 = create(:task_hook, :pre, task: task, skill: skill, on_status: "in_progress")
        hook2 = create(:task_hook, :pre, task: task, skill: create(:skill), on_status: "in_progress")
        task.lock_transition!(agent)

        pipeline_meta = {
          "task_id" => task.id,
          "new_status" => "in_progress",
          "triggering_agent_id" => agent.id,
          "context_json" => "{}",
          "phase" => "pre",
          "hook_ids" => [hook1.id, hook2.id],
          "current_hook_index" => 0
        }

        session = create(:session, agent: agent, metadata: {
          "type" => "task_hook_pipeline",
          "pipeline" => pipeline_meta
        })

        expect {
          harness.continue_task_pipeline_if_needed(session)
        }.to change(Session, :count).by(1)
          .and have_enqueued_job(ChatStreamJob)

        new_session = Session.last
        expect(new_session.metadata["pipeline"]["current_hook_index"]).to eq(1)
      end
    end

    context "post-phase completion" do
      it "unlocks the task when the last post-hook session completes" do
        hook = create(:task_hook, :post, task: task, skill: skill, on_status: "in_progress")
        task.lock_transition!(agent)

        pipeline_meta = {
          "task_id" => task.id,
          "new_status" => "in_progress",
          "triggering_agent_id" => agent.id,
          "context_json" => "{}",
          "phase" => "post",
          "hook_ids" => [hook.id],
          "current_hook_index" => 0
        }

        session = create(:session, agent: agent, metadata: {
          "type" => "task_hook_pipeline",
          "pipeline" => pipeline_meta
        })

        harness.continue_task_pipeline_if_needed(session)

        task.reload
        expect(task.transition_locked?).to be false
      end
    end

    context "agent resolution on continuation" do
      it "resolves agent fresh from task state for the next hook" do
        queen_bee = create(:agent, name: "Queen Bee")
        hook1 = create(:task_hook, :post, task: task, skill: skill, on_status: "in_progress")
        hook2 = create(:task_hook, :post, task: task, skill: create(:skill), on_status: "in_progress")
        task.lock_transition!(agent)

        # Simulate: first hook reassigned the task to Queen Bee
        task.update!(assigned_to_agent: queen_bee)

        pipeline_meta = {
          "task_id" => task.id,
          "new_status" => "in_progress",
          "triggering_agent_id" => agent.id,
          "context_json" => "{}",
          "phase" => "post",
          "hook_ids" => [hook1.id, hook2.id],
          "current_hook_index" => 0
        }

        session = create(:session, agent: agent, metadata: {
          "type" => "task_hook_pipeline",
          "pipeline" => pipeline_meta
        })

        harness.continue_task_pipeline_if_needed(session)

        # The next session should be assigned to Queen Bee (the current assignee)
        new_session = Session.last
        expect(new_session.agent).to eq(queen_bee)
      end
    end

    context "error handling" do
      it "unlocks the task if continuation fails" do
        task.lock_transition!(agent)

        pipeline_meta = {
          "task_id" => task.id,
          "new_status" => "in_progress",
          "triggering_agent_id" => agent.id,
          "context_json" => "{}",
          "phase" => "post",
          "hook_ids" => [99999], # non-existent hook
          "current_hook_index" => 0
        }

        session = create(:session, agent: agent, metadata: {
          "type" => "task_hook_pipeline",
          "pipeline" => pipeline_meta
        })

        harness.continue_task_pipeline_if_needed(session)

        task.reload
        # Should fall through to advance_to_next_phase since hook not found
        expect(task.transition_locked?).to be false
      end
    end
  end
end
