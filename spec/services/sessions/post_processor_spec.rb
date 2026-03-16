# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sessions::PostProcessor do
  let(:agent) { create(:agent, model_provider: "anthropic", llm_model: "claude-3-5-sonnet") }
  let(:session) { create(:session, agent: agent, transcript: transcript) }
  let(:transcript) { [] }
  let(:user_message) { "This is a sufficiently long user message for memory storage testing purposes" }
  let(:assistant_response) { "This is a sufficiently long assistant response for memory storage testing purposes" }
  let(:usage) { { input_tokens: 100, output_tokens: 50 } }

  before do
    allow(CostEstimator).to receive(:estimate).and_return(5)
    allow(Channels::OriginDelivery).to receive(:call)
  end

  describe ".call" do
    subject(:result) do
      described_class.call(
        agent: agent,
        session: session,
        user_message: user_message,
        assistant_response: assistant_response,
        usage: usage
      )
    end

    context "usage tracking" do
      it "creates a UsageRecord" do
        expect { result }.to change(UsageRecord, :count).by(1)
      end

      it "records correct token counts" do
        result
        record = UsageRecord.last
        expect(record.input_tokens).to eq(100)
        expect(record.output_tokens).to eq(50)
        expect(record.cost_cents).to eq(5)
        expect(record.provider).to eq("anthropic")
        expect(record.llm_model).to eq("claude-3-5-sonnet")
      end

      it "skips usage tracking when usage is blank" do
        expect {
          described_class.call(
            agent: agent, session: session,
            user_message: user_message, assistant_response: assistant_response,
            usage: {}
          )
        }.not_to change(UsageRecord, :count)
      end
    end

    context "memory storage" do
      it "does not create raw episodic MemoryEntry" do
        expect { result }.not_to change(MemoryEntry, :count)
      end

      it "enqueues MemoryExtractionJob for structured extraction" do
        expect { result }.to have_enqueued_job(MemoryExtractionJob).with(agent.id, user_message, assistant_response)
      end

      it "skips extraction for short messages" do
        expect {
          described_class.call(
            agent: agent, session: session,
            user_message: "Hi", assistant_response: "Hello",
            usage: usage
          )
        }.not_to have_enqueued_job(MemoryExtractionJob)
      end
    end

    context "summarization" do
      it "does not trigger summarization for short transcripts" do
        expect { result }.not_to have_enqueued_job(ConversationSummaryJob)
      end

      it "triggers summarization when unsummarized messages exceed threshold" do
        # SUMMARIZE_EVERY(6) + RAW_MESSAGES_TO_KEEP(4) = 10 messages needed
        session.update!(transcript: 12.times.map { |i| { "role" => i.even? ? "user" : "assistant", "content" => "msg #{i}" } })

        expect { result }.to have_enqueued_job(ConversationSummaryJob).with(session.id)
      end

      it "accounts for summary_through_index" do
        session.update!(
          transcript: 12.times.map { |i| { "role" => i.even? ? "user" : "assistant", "content" => "msg #{i}" } },
          summary_through_index: 8
        )

        # unsummarized = 12 - 8 = 4, which is < 10, so no summarization
        expect { result }.not_to have_enqueued_job(ConversationSummaryJob)
      end
    end

    context "title generation" do
      let(:two_message_transcript) do
        [
          { "role" => "user",      "content" => "How do I deploy a Rails app?" },
          { "role" => "assistant", "content" => "Use Heroku or Fly.io." }
        ]
      end

      it "enqueues SessionTitleJob when title is blank and transcript has 2+ messages" do
        session.update!(title: nil, transcript: two_message_transcript)

        expect { result }.to have_enqueued_job(SessionTitleJob).with(session.id)
      end

      it "enqueues SessionTitleJob when title is 'New Chat'" do
        session.update!(title: "New Chat", transcript: two_message_transcript)

        expect { result }.to have_enqueued_job(SessionTitleJob).with(session.id)
      end

      it "does not enqueue SessionTitleJob when title is already set to a real name" do
        session.update!(title: "My Custom Title", transcript: two_message_transcript)

        expect { result }.not_to have_enqueued_job(SessionTitleJob)
      end

      it "does not enqueue SessionTitleJob when transcript has fewer than 2 messages" do
        session.update!(title: nil, transcript: [ { "role" => "user", "content" => "Hello" } ])

        expect { result }.not_to have_enqueued_job(SessionTitleJob)
      end

      it "does not enqueue SessionTitleJob when transcript is empty" do
        session.update!(title: nil, transcript: [])

        expect { result }.not_to have_enqueued_job(SessionTitleJob)
      end

      it "continues to origin delivery even if title job enqueue raises" do
        session.update!(title: nil, transcript: two_message_transcript)
        allow(SessionTitleJob).to receive(:perform_later).and_raise(StandardError, "Queue error")

        result
        expect(Channels::OriginDelivery).to have_received(:call)
      end

      it "does not enqueue SessionTitleJob when transcript is nil" do
        session.update_columns(transcript: nil)

        expect { result }.not_to have_enqueued_job(SessionTitleJob)
      end
    end

    context "origin delivery" do
      it "calls OriginDelivery" do
        result
        expect(Channels::OriginDelivery).to have_received(:call).with(
          session: session, content: assistant_response, agent: agent
        )
      end
    end

    context "independent failure isolation" do
      it "continues memory extraction when usage tracking fails" do
        allow(UsageRecord).to receive(:create).and_raise(StandardError, "DB error")

        expect { result }.to have_enqueued_job(MemoryExtractionJob)
      end

      it "continues summarization when memory storage fails" do
        allow(MemoryEntry).to receive(:create).and_raise(StandardError, "DB error")
        session.update!(transcript: 12.times.map { |i| { "role" => i.even? ? "user" : "assistant", "content" => "msg #{i}" } })

        expect { result }.to have_enqueued_job(ConversationSummaryJob)
      end

      it "continues origin delivery when summarization fails" do
        allow(ConversationSummaryJob).to receive(:perform_later).and_raise(StandardError, "Queue error")
        session.update!(transcript: 12.times.map { |i| { "role" => i.even? ? "user" : "assistant", "content" => "msg #{i}" } })

        result
        expect(Channels::OriginDelivery).to have_received(:call)
      end

      it "returns success even when individual steps fail" do
        allow(UsageRecord).to receive(:create).and_raise(StandardError, "DB error")
        expect(result.success?).to be true
      end
    end
  end
end
