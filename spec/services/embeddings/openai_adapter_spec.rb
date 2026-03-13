# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeddings::OpenaiAdapter, type: :service do
  let(:adapter) { described_class.new }
  let(:api_key) { "sk-test-key" }

  before do
    create(:vault_entry, namespace: "provider_credentials", key: "openai_api_key", value: api_key)
  end

  describe "#capabilities" do
    it "reports text-only, cloud, flexible dimensions" do
      caps = adapter.capabilities
      expect(caps[:name]).to eq("openai")
      expect(caps[:modalities]).to eq([:text])
      expect(caps[:local]).to be false
      expect(caps[:dimensions]).to include(768, 1536, 3072)
    end
  end

  describe "#embed_text" do
    it "returns a vector from OpenAI" do
      vector = Array.new(768) { rand }
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 200, body: { data: [{ embedding: vector }] }.to_json)

      result = adapter.embed_text("hello world")
      expect(result).to eq(vector)
    end

    it "returns nil when API key is missing" do
      VaultEntry.destroy_all
      expect(described_class.new.embed_text("test")).to be_nil
    end

    it "returns nil on API error" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 429, body: { error: { message: "rate limited" } }.to_json)

      expect(adapter.embed_text("test")).to be_nil
    end
  end

  describe "#healthy?" do
    it "returns true when API key exists in vault" do
      expect(adapter.healthy?).to be true
    end

    it "returns false when API key is missing" do
      VaultEntry.destroy_all
      expect(described_class.new.healthy?).to be false
    end
  end

  describe "#cost_per_million_tokens" do
    it "returns the OpenAI pricing" do
      expect(adapter.cost_per_million_tokens).to eq(0.02)
    end
  end
end
