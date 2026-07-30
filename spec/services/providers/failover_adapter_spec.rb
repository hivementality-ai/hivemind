# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::FailoverAdapter, type: :service do
  let(:agent) do
    create(:agent, model_provider: "anthropic", model_config: {
      "fallback_models" => [ { "provider" => "openai", "model" => "gpt-4o" } ]
    })
  end

  let(:primary) { instance_double(Providers::AnthropicAdapter) }
  let(:fallback) { instance_double(Providers::OpenaiAdapter) }
  let(:messages) { [ { role: "user", content: "Hi" } ] }
  let(:adapter) { described_class.new(primary: primary, chain: agent.fallback_models, agent: agent) }

  let(:success) { ServiceResponse.success(data: { content: "ok", usage: { input_tokens: 1 } }) }

  before do
    allow(Providers::Resolver).to receive(:call)
      .with(provider_name: "openai", agent: agent, failover: false)
      .and_return(ServiceResponse.success(data: { adapter: fallback }))
  end

  def failure(msg) = ServiceResponse.failure(error: msg)

  describe "#chat" do
    it "returns the primary result untouched on success" do
      allow(primary).to receive(:chat).and_return(success)

      result = adapter.chat(messages: messages)

      expect(result).to be_success
      expect(result.data[:usage]).not_to have_key(:fallback_model)
      expect(Providers::Resolver).not_to have_received(:call)
    end

    %w[
      429 500 502 503 529
    ].each do |status|
      it "falls back to the next model on a #{status} error" do
        allow(primary).to receive(:chat).and_return(failure("Anthropic API error (#{status}): unavailable"))
        allow(fallback).to receive(:chat).and_return(success)

        result = adapter.chat(messages: messages, options: { model: "claude-x" })

        expect(result).to be_success
        expect(fallback).to have_received(:chat)
          .with(messages: messages, tools: [], options: { model: "gpt-4o" })
      end
    end

    it "falls back on timeouts and connection errors" do
      allow(primary).to receive(:chat).and_return(failure("Anthropic API error: execution expired"))
      allow(fallback).to receive(:chat).and_return(success)

      expect(adapter.chat(messages: messages)).to be_success
    end

    it "falls back on auth failures" do
      allow(primary).to receive(:chat).and_return(failure("OpenAI API error: the server responded with status 401"))
      allow(fallback).to receive(:chat).and_return(success)

      expect(adapter.chat(messages: messages)).to be_success
    end

    it "tags usage and records an audit log when a fallback succeeds" do
      allow(primary).to receive(:chat).and_return(failure("Anthropic API error (429): rate limited"))
      allow(fallback).to receive(:chat).and_return(success)

      result = nil
      expect { result = adapter.chat(messages: messages) }.to change(AuditLog, :count).by(1)

      expect(result.data[:usage][:fallback_model]).to eq("openai/gpt-4o")
      log = AuditLog.last
      expect(log.action).to eq("llm_failover")
      expect(log.resource).to eq("openai/gpt-4o")
      expect(log.metadata["error"]).to include("429")
    end

    it "does NOT fall back on content/validation errors" do
      original = failure("Anthropic API error (400): messages: text content blocks must be non-empty")
      allow(primary).to receive(:chat).and_return(original)

      result = adapter.chat(messages: messages)

      expect(result).to be(original)
      expect(Providers::Resolver).not_to have_received(:call)
    end

    it "lets PromptTooLongError propagate for ToolLoop's auto-compact" do
      allow(primary).to receive(:chat).and_raise(PromptTooLongError, "prompt is too long")

      expect { adapter.chat(messages: messages) }.to raise_error(PromptTooLongError)
    end

    it "returns the original-style error when the chain is exhausted" do
      allow(primary).to receive(:chat).and_return(failure("Anthropic API error (503): overloaded"))
      allow(fallback).to receive(:chat).and_return(failure("OpenAI API error: the server responded with status 500"))

      result = adapter.chat(messages: messages)

      expect(result).not_to be_success
      expect(result.error).to include("Anthropic API error (503): overloaded")
      expect(result.error).to include("fallback model(s) also unavailable")
    end

    it "stops the chain when a fallback fails with a non-retryable error" do
      allow(primary).to receive(:chat).and_return(failure("Anthropic API error (429): rate limited"))
      bad_request = failure("OpenAI API error: the server responded with status 400")
      allow(fallback).to receive(:chat).and_return(bad_request)

      expect(adapter.chat(messages: messages)).to be(bad_request)
    end

    it "skips chain entries whose provider cannot be resolved" do
      allow(Providers::Resolver).to receive(:call)
        .with(provider_name: "openai", agent: agent, failover: false)
        .and_return(ServiceResponse.failure(error: "Provider not found: openai"))
      allow(primary).to receive(:chat).and_return(failure("Anthropic API error (529): overloaded"))

      result = adapter.chat(messages: messages)

      expect(result).not_to be_success
      expect(result.error).to include("Anthropic API error (529)")
    end
  end

  describe "Agent#fallback_models" do
    it "parses bare model strings against the agent's own provider" do
      agent = build(:agent, model_provider: "anthropic", model_config: { "fallback_models" => [ "claude-haiku" ] })

      expect(agent.fallback_models).to eq([ { provider: "anthropic", model: "claude-haiku" } ])
    end

    it "parses provider/model hashes and drops malformed entries" do
      agent = build(:agent, model_provider: "anthropic", model_config: {
        "fallback_models" => [ { "provider" => "openai", "model" => "gpt-4o" }, { "provider" => "openai" }, "", nil, 42 ]
      })

      expect(agent.fallback_models).to eq([ { provider: "openai", model: "gpt-4o" } ])
    end

    it "is empty when unconfigured" do
      expect(build(:agent, model_config: nil).fallback_models).to eq([])
    end
  end
end
