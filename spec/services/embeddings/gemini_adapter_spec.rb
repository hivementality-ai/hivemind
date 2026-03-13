# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeddings::GeminiAdapter, type: :service do
  let(:adapter) { described_class.new }
  let(:api_key) { "test-google-ai-key" }
  let(:model) { Embeddings::GeminiAdapter::MODEL }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_AI_API_KEY").and_return(api_key)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("MEMORY_GEMINI_MODEL", model).and_return(model)
    allow(ENV).to receive(:fetch).with("MEMORY_EMBEDDING_DIMENSIONS", 768).and_return(768)
  end

  describe "#capabilities" do
    it "reports multimodal, cloud, multiple dimension options" do
      caps = adapter.capabilities
      expect(caps[:name]).to eq("gemini")
      expect(caps[:modalities]).to include(:text, :image, :audio)
      expect(caps[:local]).to be false
      expect(caps[:dimensions]).to include(768, 1536, 3072)
    end
  end

  describe "#embed_text" do
    it "calls Gemini API with RETRIEVAL_DOCUMENT task type" do
      vector = Array.new(768) { rand }
      stub = stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/#{model}:embedContent?key=#{api_key}")
        .with(body: hash_including("taskType" => "RETRIEVAL_DOCUMENT"))
        .to_return(status: 200, body: { embedding: { values: vector } }.to_json)

      result = adapter.embed_text("document text")
      expect(result).to eq(vector)
      expect(stub).to have_been_requested
    end

    it "returns nil when API key is missing" do
      allow(ENV).to receive(:[]).with("GOOGLE_AI_API_KEY").and_return(nil)
      allow(VaultEntry).to receive(:find_by).and_return(nil)

      expect(adapter.embed_text("test")).to be_nil
    end

    it "returns nil on API error" do
      stub_request(:post, /generativelanguage\.googleapis\.com/)
        .to_return(status: 400, body: { error: { message: "bad request" } }.to_json)

      expect(adapter.embed_text("test")).to be_nil
    end
  end

  describe "#embed_query" do
    it "calls Gemini API with RETRIEVAL_QUERY task type" do
      vector = Array.new(768) { rand }
      stub = stub_request(:post, "https://generativelanguage.googleapis.com/v1beta/models/#{model}:embedContent?key=#{api_key}")
        .with(body: hash_including("taskType" => "RETRIEVAL_QUERY"))
        .to_return(status: 200, body: { embedding: { values: vector } }.to_json)

      result = adapter.embed_query("search query")
      expect(result).to eq(vector)
      expect(stub).to have_been_requested
    end
  end

  describe "#healthy?" do
    it "returns true when API key is present" do
      expect(adapter.healthy?).to be true
    end

    it "returns false when API key is missing" do
      allow(ENV).to receive(:[]).with("GOOGLE_AI_API_KEY").and_return(nil)
      allow(VaultEntry).to receive(:find_by).and_return(nil)

      expect(described_class.new.healthy?).to be false
    end
  end

  describe "#cost_per_million_tokens" do
    it "returns the Gemini pricing" do
      expect(adapter.cost_per_million_tokens).to eq(0.10)
    end
  end
end
