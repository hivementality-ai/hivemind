# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::Resolver do
  before { VaultEntry.where(namespace: "search").destroy_all }

  describe ".provider" do
    it "returns DuckDuckGo when nothing configured" do
      expect(described_class.provider).to be_a(Search::Duckduckgo)
    end

    it "returns DuckDuckGo when provider set but no API key" do
      VaultEntry.create!(namespace: "search", key: "provider", encrypted_value: "brave")
      expect(described_class.provider).to be_a(Search::Duckduckgo)
    end

    it "returns Brave when configured with key" do
      VaultEntry.create!(namespace: "search", key: "provider", encrypted_value: "brave")
      VaultEntry.create!(namespace: "search", key: "api_key", encrypted_value: "test-key")
      expect(described_class.provider).to be_a(Search::Brave)
    end

    it "returns SearchAPI when configured" do
      VaultEntry.create!(namespace: "search", key: "provider", encrypted_value: "searchapi")
      VaultEntry.create!(namespace: "search", key: "api_key", encrypted_value: "test-key")
      expect(described_class.provider).to be_a(Search::Searchapi)
    end

    it "returns SerpAPI when configured" do
      VaultEntry.create!(namespace: "search", key: "provider", encrypted_value: "serpapi")
      VaultEntry.create!(namespace: "search", key: "api_key", encrypted_value: "test-key")
      expect(described_class.provider).to be_a(Search::Serpapi)
    end
  end

  describe ".configured?" do
    it "returns false with no config" do
      expect(described_class.configured?).to be false
    end

    it "returns false for duckduckgo" do
      VaultEntry.create!(namespace: "search", key: "provider", encrypted_value: "duckduckgo")
      expect(described_class.configured?).to be false
    end

    it "returns true with provider and key" do
      VaultEntry.create!(namespace: "search", key: "provider", encrypted_value: "brave")
      VaultEntry.create!(namespace: "search", key: "api_key", encrypted_value: "test-key")
      expect(described_class.configured?).to be true
    end
  end
end
