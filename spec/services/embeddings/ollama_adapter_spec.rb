# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeddings::OllamaAdapter, type: :service do
  let(:adapter) { described_class.new }
  let(:base_url) { "http://localhost:11434" }

  before do
    # OllamaAdapter#base_url queries by adapter_type only (no enabled: true filter)
    # so it works for both chat-enabled and embedding-only configs.
    allow(ProviderConfig).to receive(:find_by).with(adapter_type: "ollama").and_return(nil)
  end

  describe "#capabilities" do
    it "reports text-only, local, 768 dimensions" do
      caps = adapter.capabilities
      expect(caps[:name]).to eq("ollama")
      expect(caps[:modalities]).to eq([ :text ])
      expect(caps[:local]).to be true
      expect(caps[:default_dimensions]).to eq(768)
    end
  end

  describe "#embed_text" do
    it "returns a vector from Ollama" do
      vector = Array.new(768) { rand }
      stub_request(:post, "#{base_url}/api/embeddings")
        .to_return(status: 200, body: { embedding: vector }.to_json)

      result = adapter.embed_text("hello world")
      expect(result).to be_an(Array)
      expect(result.length).to eq(768)
    end

    it "returns nil on API error" do
      stub_request(:post, "#{base_url}/api/embeddings")
        .to_return(status: 500, body: "error")

      expect(adapter.embed_text("hello")).to be_nil
    end
  end

  describe "#embed_query" do
    it "delegates to embed_text (symmetric model)" do
      vector = Array.new(768) { rand }
      stub_request(:post, "#{base_url}/api/embeddings")
        .to_return(status: 200, body: { embedding: vector }.to_json)

      result = adapter.embed_query("search query")
      expect(result.length).to eq(768)
    end
  end

  describe "#healthy?" do
    it "returns true when Ollama is reachable" do
      stub_request(:get, "#{base_url}/api/tags")
        .to_return(status: 200, body: { models: [] }.to_json)

      expect(adapter.healthy?).to be true
    end

    it "returns false when Ollama is unreachable" do
      stub_request(:get, "#{base_url}/api/tags").to_timeout

      expect(adapter.healthy?).to be false
    end
  end

  describe "#cost_per_million_tokens" do
    it "is nil (free/local)" do
      expect(adapter.cost_per_million_tokens).to be_nil
    end
  end
end
