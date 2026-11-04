# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationSummaryJob, type: :job do
  let(:agent)   { create(:agent, model_provider: "anthropic", llm_model: "claude-opus-4-7") }
  let(:adapter) { instance_double(Providers::AnthropicAdapter) }
  let(:transcript) do
    Array.new(8) { |i| { "role" => i.even? ? "user" : "assistant", "content" => "message #{i}" } }
  end
  let(:session) { create(:session, agent:, transcript:) }

  before do
    allow(Providers::Resolver).to receive(:call).and_return(double(success?: true, data: { adapter: adapter }))
    allow(adapter).to receive(:chat).and_return(double(success?: true, data: { content: "A summary." }))
  end

  it "requests the background model rather than the agent's main model" do
    described_class.perform_now(session.id)

    expect(adapter).to have_received(:chat).once.with(
      hash_including(options: hash_including(model: LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER))
    )
    expect(session.reload.conversation_summary).to eq("A summary.")
  end
end
