# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memory::Embedding, type: :service do
  describe "unreachable provider" do
    let(:adapter) { instance_double(Embeddings::OllamaAdapter) }

    before do
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)
      allow(adapter).to receive(:embed_text).and_raise(Faraday::ConnectionFailed, "refused")
      allow(adapter).to receive(:embed_query).and_raise(Faraday::TimeoutError, "timed out")
      allow(Rails.logger).to receive(:warn)
    end

    it "generate_query returns nil and logs one warning" do
      expect(described_class.generate_query("hi")).to be_nil
      expect(Rails.logger).to have_received(:warn).once
    end

    it "generate returns nil by default" do
      expect(described_class.generate("hi")).to be_nil
    end

    it "generate raises TransientProviderError when asked" do
      expect { described_class.generate("hi", raise_unreachable: true) }
        .to raise_error(TransientProviderError)
    end
  end

  describe ".generate" do
    it "returns nil for blank text" do
      expect(described_class.generate("")).to be_nil
      expect(described_class.generate(nil)).to be_nil
    end

    it "delegates to the current adapter's embed_text" do
      vector = Array.new(768) { rand }
      adapter = instance_double(Embeddings::OllamaAdapter)
      allow(adapter).to receive(:embed_text).with("hello").and_return(vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      expect(described_class.generate("hello")).to eq(vector)
    end

    it "uses a specific provider when requested" do
      vector = Array.new(768) { rand }
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:embed_text).with("hello").and_return(vector)
      allow(Embeddings::Registry).to receive(:adapter_for).with("gemini").and_return(adapter)

      expect(described_class.generate("hello", provider: "gemini")).to eq(vector)
    end

    it "returns nil when no adapter is available" do
      allow(Embeddings::Registry).to receive(:current).and_return(nil)
      expect(described_class.generate("hello")).to be_nil
    end

    it "returns nil and logs on error" do
      adapter = instance_double(Embeddings::OllamaAdapter)
      allow(adapter).to receive(:embed_text).and_raise(StandardError, "connection refused")
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      expect(Rails.logger).to receive(:error).with(/Failed to generate embedding/)
      expect(described_class.generate("hello")).to be_nil
    end
  end

  describe ".generate_query" do
    it "delegates to the current adapter's embed_query" do
      vector = Array.new(768) { rand }
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:embed_query).with("search terms").and_return(vector)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      expect(described_class.generate_query("search terms")).to eq(vector)
    end
  end

  describe ".available?" do
    it "returns true when the current adapter is healthy" do
      adapter = instance_double(Embeddings::OllamaAdapter, healthy?: true)
      allow(Embeddings::Registry).to receive(:current).and_return(adapter)

      expect(described_class.available?).to be true
    end

    it "returns false when no adapter is configured" do
      allow(Embeddings::Registry).to receive(:current).and_return(nil)

      expect(described_class.available?).to be false
    end
  end

  describe ".provider_name" do
    it "returns the configured provider name" do
      allow(Embeddings::Registry).to receive(:configured_provider).and_return("gemini")
      expect(described_class.provider_name).to eq("gemini")
    end
  end
end
