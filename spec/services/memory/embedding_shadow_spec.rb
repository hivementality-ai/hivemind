# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Memory::Embedding shadow/migration support", type: :service do
  describe ".migration_active?" do
    it "returns false when setting is not set" do
      expect(Memory::Embedding.migration_active?).to be false
    end

    it "returns true when setting is 'true'" do
      Setting.set("embedding_migration_active", "true")
      expect(Memory::Embedding.migration_active?).to be true
    end

    it "returns false when setting is 'false'" do
      Setting.set("embedding_migration_active", "false")
      expect(Memory::Embedding.migration_active?).to be false
    end
  end

  describe ".generate_shadow" do
    it "returns nil when no migration is active" do
      expect(Memory::Embedding.generate_shadow("hello")).to be_nil
    end

    it "generates embedding from target provider when migration is active" do
      Setting.set("embedding_migration_active", "true")
      Setting.set("embedding_migration_target", "gemini")

      fake_vector = Array.new(768) { rand }
      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:embed_text).and_return(fake_vector)
      allow(Embeddings::Registry).to receive(:adapter_for).with("gemini").and_return(adapter)

      result = Memory::Embedding.generate_shadow("test text")
      expect(result).to eq(fake_vector)
      expect(adapter).to have_received(:embed_text).with("test text")
    end

    it "returns nil on error without raising" do
      Setting.set("embedding_migration_active", "true")
      Setting.set("embedding_migration_target", "gemini")

      adapter = instance_double(Embeddings::GeminiAdapter)
      allow(adapter).to receive(:embed_text).and_raise(StandardError, "API down")
      allow(Embeddings::Registry).to receive(:adapter_for).with("gemini").and_return(adapter)

      expect(Memory::Embedding.generate_shadow("test")).to be_nil
    end

    it "returns nil for blank text" do
      Setting.set("embedding_migration_active", "true")
      Setting.set("embedding_migration_target", "gemini")

      expect(Memory::Embedding.generate_shadow("")).to be_nil
      expect(Memory::Embedding.generate_shadow(nil)).to be_nil
    end
  end
end
