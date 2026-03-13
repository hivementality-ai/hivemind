# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::ResolvePendingQuestion, type: :service do
  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent, transcript: []) }

  describe ".call" do
    context "when no pending question exists" do
      it "returns failure" do
        result = described_class.call(session: session, user_message: "hello")
        expect(result).not_to be_success
        expect(result.error).to eq("no_pending_question")
      end
    end

    context "when a pending question exists" do
      before do
        Rails.cache.write("ask_user_pending:#{session.id}", {
          timeout_at: 5.minutes.from_now.iso8601,
          question: "What color?"
        }.to_json, expires_in: 300)
      end

      it "stores the answer and returns success" do
        result = described_class.call(session: session, user_message: "blue")
        expect(result).to be_success

        cached = JSON.parse(Rails.cache.read("ask_user_pending:#{session.id}"))
        expect(cached["answer"]).to eq("blue")
        expect(cached["answered_at"]).to be_present
      end

      it "adds to transcript with is_question_response flag" do
        described_class.call(session: session, user_message: "blue")
        session.reload

        last_entry = session.transcript.last
        expect(last_entry["role"]).to eq("user")
        expect(last_entry["content"]).to eq("blue")
        expect(last_entry["is_question_response"]).to be true
      end

      it "broadcasts user message via ActionCable" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "session_#{session.id}",
          { type: "user_message", content: "blue" }
        )

        described_class.call(session: session, user_message: "blue")
      end
    end

    context "when the question has timed out" do
      before do
        Rails.cache.write("ask_user_pending:#{session.id}", {
          timeout_at: 5.minutes.ago.iso8601,
          question: "What color?"
        }.to_json, expires_in: 300)
      end

      it "returns failure and clears cache" do
        result = described_class.call(session: session, user_message: "blue")
        expect(result).not_to be_success
        expect(result.error).to eq("question_timed_out")
        expect(Rails.cache.read("ask_user_pending:#{session.id}")).to be_nil
      end
    end
  end
end
