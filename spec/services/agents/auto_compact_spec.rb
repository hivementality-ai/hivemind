# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::AutoCompact do
  let(:agent) { build_stubbed(:agent) }

  let(:messages) do
    [
      { role: "user", content: "please build X" },
      { role: "assistant", content: "working on it" },
      { role: "tool", tool_use_id: "t1", tool_name: "file_read", content: "file bytes" },
      { role: "user", content: "thanks" }
    ]
  end

  describe ".call" do
    context "when no Anthropic provider is configured" do
      before { allow(ProviderConfig).to receive_message_chain(:enabled_providers, :find_by).and_return(nil) }

      it "returns nil so the caller can fall back to hard_prune" do
        expect(described_class.call(messages, agent: agent)).to be_nil
      end
    end

    context "when the haiku client returns a summary" do
      let(:fake_client) { instance_double(Providers::AnthropicAdapter) }
      let(:summary_response) { ServiceResponse.success(data: { content: "- Built X\n- Currently: thanking user\n- Decision: use approach Y" }) }

      before do
        allow(described_class).to receive(:haiku_client).with(agent: agent).and_return(fake_client)
        allow(fake_client).to receive(:chat).and_return(summary_response)
      end

      it "returns a single compacted user message" do
        result = described_class.call(messages, agent: agent)

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
        expect(result.first["role"]).to eq("user")
        expect(result.first["content"]).to start_with("[Context compacted]")
        expect(result.first["content"]).to include("Built X")
      end

      it "pins the summarization call to Haiku" do
        described_class.call(messages, agent: agent)
        expect(fake_client).to have_received(:chat).with(
          hash_including(options: hash_including(model: described_class::SUMMARIZATION_MODEL))
        )
      end
    end

    context "when the summarization call fails" do
      let(:fake_client) { instance_double(Providers::AnthropicAdapter) }

      before do
        allow(described_class).to receive(:haiku_client).with(agent: agent).and_return(fake_client)
        allow(fake_client).to receive(:chat).and_return(ServiceResponse.failure(error: "Network down"))
      end

      it "returns nil" do
        expect(described_class.call(messages, agent: agent)).to be_nil
      end
    end

    context "when the summarization call raises" do
      let(:fake_client) { instance_double(Providers::AnthropicAdapter) }

      before do
        allow(described_class).to receive(:haiku_client).with(agent: agent).and_return(fake_client)
        allow(fake_client).to receive(:chat).and_raise(StandardError, "boom")
      end

      it "rescues and returns nil" do
        expect(described_class.call(messages, agent: agent)).to be_nil
      end
    end
  end

  describe ".serialize_tail" do
    it "returns the full JSON when under the byte cap" do
      result = described_class.serialize_tail([ { a: 1 } ], 10_000)
      expect(JSON.parse(result)).to eq([ { "a" => 1 } ])
    end

    it "truncates to the tail when over the cap" do
      big = (1..1000).map { |i| { role: "user", content: "msg #{i} #{'x' * 100}" } }
      result = described_class.serialize_tail(big, 1000)
      expect(result.length).to be <= 1000
    end
  end
end
