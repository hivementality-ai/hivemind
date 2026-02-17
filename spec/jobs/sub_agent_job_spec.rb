# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubAgentJob, type: :job do
  let(:parent_agent) { create(:agent, name: "Parent") }
  let(:child_agent) { create(:agent, name: "Child") }
  let(:parent_session) { create(:session, agent: parent_agent) }
  let(:task) { create(:sub_agent_task, parent_agent: parent_agent, child_agent: child_agent, parent_session: parent_session, task: "Analyze data") }

  before do
    allow(ActionCable.server).to receive(:broadcast)
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

      it "notifies parent via ActionCable" do
        described_class.perform_now(task.id)
        expect(ActionCable.server).to have_received(:broadcast).with(
          "session_#{parent_session.session_key}",
          hash_including(type: "sub_agent_complete", child_agent: "Child")
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
    end

    context "without parent session" do
      let(:task) { create(:sub_agent_task, parent_agent: parent_agent, child_agent: child_agent, parent_session: nil, task: "Do stuff") }

      before do
        allow(Sessions::Chat).to receive(:call).and_return(
          double(success?: true, data: { reply: "Done" })
        )
      end

      it "does not broadcast when no parent session" do
        described_class.perform_now(task.id)
        expect(ActionCable.server).not_to have_received(:broadcast)
      end
    end
  end
end
