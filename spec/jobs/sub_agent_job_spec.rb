# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubAgentJob, type: :job do
  let(:parent_agent) { create(:agent, name: "Parent") }
  let(:child_agent) { create(:agent, name: "Child") }
  let(:parent_session) { create(:session, agent: parent_agent) }
  let(:task) do
    create(:sub_agent_task,
           parent_agent: parent_agent,
           child_agent: child_agent,
           parent_session: parent_session,
           task: "Analyze data")
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
    allow(ChatStreamJob).to receive(:perform_later)
  end

  describe "#perform" do
    context "success" do
      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          double(success?: true, data: { reply: "Analysis complete" })
        )
      end

      it "sets task to running with started_at" do
        described_class.perform_now(task.id)
        task.reload
        expect(task.started_at).to be_present
      end

      it "creates isolated session for child agent" do
        described_class.perform_now(task.id)
        new_session = Session.find_by(session_key: "sub-#{task.task_key}")
        expect(new_session).to be_present
        expect(new_session.agent).to eq(child_agent)
        expect(new_session.metadata["type"]).to eq("sub_agent")
      end

      it "calls Sessions::Chat with task message" do
        described_class.perform_now(task.id)
        expect(Sessions::Chat).to have_received(:call).with(
          hash_including(message: "Analyze data", agent: child_agent)
        )
      end

      it "updates status to completed and stores result" do
        described_class.perform_now(task.id)
        task.reload
        expect(task.status).to eq("completed")
        expect(task.result).to eq("Analysis complete")
        expect(task.completed_at).to be_present
      end

      it "fires ChatStreamJob callback to parent session" do
        described_class.perform_now(task.id)
        expect(ChatStreamJob).to have_received(:perform_later).with(
          parent_session.id,
          a_string_matching(/\[Sub-agent result.*Child.*Analyze data/),
          []
        )
      end

      it "includes result in callback message" do
        described_class.perform_now(task.id)
        expect(ChatStreamJob).to have_received(:perform_later).with(
          parent_session.id,
          a_string_matching(/Analysis complete/),
          []
        )
      end
    end

    context "Chat failure" do
      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          double(success?: false, error: "Model unavailable")
        )
      end

      it "updates status to failed" do
        described_class.perform_now(task.id)
        task.reload
        expect(task.status).to eq("failed")
        expect(task.result).to include("Model unavailable")
      end

      it "still fires callback to parent with failure info" do
        described_class.perform_now(task.id)
        expect(ChatStreamJob).to have_received(:perform_later).with(
          parent_session.id,
          a_string_matching(/Sub-agent failed.*Model unavailable/),
          []
        )
      end
    end

    context "exception" do
      before do
        allow(Sessions::Chat).to receive(:call).and_raise(StandardError, "Connection timeout")
      end

      it "updates status to failed with error message" do
        described_class.perform_now(task.id)
        task.reload
        expect(task.status).to eq("failed")
        expect(task.result).to include("Connection timeout")
      end

      it "fires error callback to parent" do
        described_class.perform_now(task.id)
        expect(ChatStreamJob).to have_received(:perform_later).with(
          parent_session.id,
          a_string_matching(/Sub-agent error.*Connection timeout/),
          []
        )
      end
    end

    context "without parent session" do
      let(:task) do
        create(:sub_agent_task,
               parent_agent: parent_agent,
               child_agent: child_agent,
               parent_session: nil,
               task: "Do stuff")
      end

      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          double(success?: true, data: { reply: "Done" })
        )
      end

      it "does not fire callback when no parent session" do
        described_class.perform_now(task.id)
        expect(ChatStreamJob).not_to have_received(:perform_later)
      end
    end

    context "recursion depth limit" do
      it "stops callbacks at MAX_CALLBACK_DEPTH" do
        allow(Sessions::Chat).to receive(:call).and_return(
          double(success?: true, data: { reply: "Done" })
        )

        # Create a chain of sub-agent sessions to simulate depth
        grandparent_session = create(:session, agent: parent_agent)
        grandparent_task = create(:sub_agent_task,
                                  parent_agent: parent_agent,
                                  child_agent: parent_agent,
                                  parent_session: grandparent_session,
                                  task: "Level 0")

        mid_session = create(:session, agent: parent_agent,
                             metadata: { "type" => "sub_agent", "parent_task_id" => grandparent_task.id })
        mid_task = create(:sub_agent_task,
                          parent_agent: parent_agent,
                          child_agent: parent_agent,
                          parent_session: mid_session,
                          task: "Level 1")

        deep_session = create(:session, agent: parent_agent,
                              metadata: { "type" => "sub_agent", "parent_task_id" => mid_task.id })
        deeper_task = create(:sub_agent_task,
                             parent_agent: parent_agent,
                             child_agent: parent_agent,
                             parent_session: deep_session,
                             task: "Level 2")

        deepest_session = create(:session, agent: parent_agent,
                                 metadata: { "type" => "sub_agent", "parent_task_id" => deeper_task.id })
        deepest_task = create(:sub_agent_task,
                              parent_agent: parent_agent,
                              child_agent: child_agent,
                              parent_session: deepest_session,
                              task: "Level 3 — should be depth-limited")

        described_class.perform_now(deepest_task.id)

        # Should NOT fire ChatStreamJob (depth limited)
        expect(ChatStreamJob).not_to have_received(:perform_later)
        # Should still broadcast completion to ActionCable
        expect(ActionCable.server).to have_received(:broadcast).with(
          "session_#{deepest_session.id}",
          hash_including(type: "sub_agent_complete", depth_limited: true)
        )
      end
    end
  end
end
