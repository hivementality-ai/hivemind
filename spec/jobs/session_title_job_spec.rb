# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionTitleJob, type: :job do
  let(:agent)   { create(:agent, model_provider: "anthropic", llm_model: "claude-haiku-4-5") }
  let(:adapter) { instance_double(Providers::AnthropicAdapter) }
  let(:resolver_success) { double(success?: true, data: { adapter: adapter }) }
  let(:resolver_failure) { double(success?: false) }

  let(:two_message_transcript) do
    [
      { "role" => "user",      "content" => "How do I deploy a Rails app?" },
      { "role" => "assistant", "content" => "You can use Heroku or Fly.io." }
    ]
  end

  before do
    allow(Providers::Resolver).to receive(:call).and_return(resolver_success)
    allow(ActionCable.server).to receive(:broadcast)
    allow(CostEstimator).to receive(:estimate).and_return(0)
  end

  def stub_llm_title(title)
    allow(adapter).to receive(:chat).and_return(
      double(success?: true, data: { content: title, usage: { input_tokens: 10, output_tokens: 5 } })
    )
  end

  def stub_llm_failure
    allow(adapter).to receive(:chat).and_return(double(success?: false))
  end

  # ── Happy path ────────────────────────────────────────────────────────────

  describe "happy path" do
    it "generates a title when session has no title" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      stub_llm_title("Deploying Rails to Production")

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Deploying Rails to Production")
    end

    it "generates a title when session title is blank string" do
      session = create(:session, agent: agent, title: "", transcript: two_message_transcript)
      stub_llm_title("Deploying Rails to Production")

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Deploying Rails to Production")
    end

    it "generates a title when session title is 'New Chat'" do
      session = create(:session, agent: agent, title: "New Chat", transcript: two_message_transcript)
      stub_llm_title("Deploying Rails to Production")

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Deploying Rails to Production")
    end

    it "broadcasts title_update over the session channel" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      stub_llm_title("Deploying Rails to Production")

      described_class.perform_now(session.id)

      expect(ActionCable.server).to have_received(:broadcast).with(
        "session_#{session.id}",
        { type: "title_update", title: "Deploying Rails to Production" }
      )
    end

    it "strips surrounding quotes from LLM output" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      stub_llm_title('"Deploying Rails to Production"')

      described_class.perform_now(session.id)

      expect(session.reload.title).to eq("Deploying Rails to Production")
    end

    it "creates a UsageRecord after a successful title generation" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      stub_llm_title("Deploying Rails to Production")

      expect {
        described_class.perform_now(session.id)
      }.to change(UsageRecord, :count).by(1)
    end
  end

  # ── Guard conditions — should not generate ────────────────────────────────

  describe "guard: title already set" do
    it "does not overwrite a user-set title" do
      session = create(:session, agent: agent, title: "My Custom Title", transcript: two_message_transcript)

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
      expect(session.reload.title).to eq("My Custom Title")
    end

    it "does not broadcast or track usage when atomic update finds title already changed" do
      session = create(:session, agent: agent, title: "New Chat", transcript: two_message_transcript)

      # Simulate race: another job sets the title between our LLM call and our update_all
      allow(Session).to receive(:where).and_call_original
      allow(Session).to receive(:where).with(id: session.id, title: [nil, "", "New Chat"]).and_wrap_original do |m, *args|
        session.update_columns(title: "Set By Other Job")
        m.call(*args)
      end

      stub_llm_title("Should Not Win")
      described_class.perform_now(session.id)

      expect(ActionCable.server).not_to have_received(:broadcast)
      expect(UsageRecord.count).to eq(0)
    end
  end

  describe "guard: transcript too short" do
    it "does not generate a title with only one message" do
      session = create(:session, agent: agent, title: nil,
                       transcript: [{ "role" => "user", "content" => "Hello" }])

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
    end

    it "does not generate a title with an empty transcript" do
      session = create(:session, agent: agent, title: nil, transcript: [])

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
    end
  end

  describe "guard: provider resolver fails" do
    it "does nothing when the provider cannot be resolved" do
      allow(Providers::Resolver).to receive(:call).and_return(resolver_failure)
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)

      described_class.perform_now(session.id)

      expect(adapter).not_to have_received(:chat)
    end
  end

  # ── LLM failure handling ──────────────────────────────────────────────────

  describe "LLM failure handling" do
    it "does not set title when LLM returns failure result" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      stub_llm_failure

      described_class.perform_now(session.id)

      expect(session.reload.title).to be_blank
    end

    it "does not set title when LLM returns blank content" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      allow(adapter).to receive(:chat).and_return(
        double(success?: true, data: { content: "   ", usage: {} })
      )

      described_class.perform_now(session.id)

      expect(session.reload.title).to be_blank
    end

    it "does not raise — swallows StandardError and logs a warning" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      allow(adapter).to receive(:chat).and_raise(StandardError, "network timeout")

      expect { described_class.perform_now(session.id) }.not_to raise_error
    end
  end

  # ── Edge cases ────────────────────────────────────────────────────────────

  describe "edge cases" do
    it "truncates titles longer than 100 characters" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      stub_llm_title("A" * 150)

      described_class.perform_now(session.id)

      expect(session.reload.title.length).to eq(100)
    end

    it "uses the cheapest model (haiku) for anthropic provider" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)

      captured_options = nil
      allow(adapter).to receive(:chat) do |**kwargs|
        captured_options = kwargs[:options]
        double(success?: true, data: { content: "Short Title", usage: { input_tokens: 5, output_tokens: 3 } })
      end

      described_class.perform_now(session.id)

      expect(captured_options[:model]).to eq("claude-haiku-4-5")
    end

    it "caps LLM response at 30 tokens" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)

      captured_options = nil
      allow(adapter).to receive(:chat) do |**kwargs|
        captured_options = kwargs[:options]
        double(success?: true, data: { content: "Title", usage: { input_tokens: 5, output_tokens: 3 } })
      end

      described_class.perform_now(session.id)

      expect(captured_options[:max_tokens]).to eq(30)
    end

    it "handles nil transcript gracefully" do
      session = create(:session, agent: agent, title: nil, transcript: nil)

      expect { described_class.perform_now(session.id) }.not_to raise_error
      expect(adapter).not_to have_received(:chat)
    end

    it "does not create a UsageRecord when usage data is nil" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      allow(adapter).to receive(:chat).and_return(
        double(success?: true, data: { content: "Good Title", usage: nil })
      )

      expect {
        described_class.perform_now(session.id)
      }.not_to change(UsageRecord, :count)
    end

    it "does not create a UsageRecord when both token counts are zero" do
      session = create(:session, agent: agent, title: nil, transcript: two_message_transcript)
      allow(adapter).to receive(:chat).and_return(
        double(success?: true, data: { content: "Good Title", usage: { input_tokens: 0, output_tokens: 0 } })
      )

      expect {
        described_class.perform_now(session.id)
      }.not_to change(UsageRecord, :count)
    end
  end
end
