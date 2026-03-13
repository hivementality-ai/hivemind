# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeddings::Registry, type: :service do
  describe ".adapter_for" do
    it "returns an OllamaAdapter for 'ollama'" do
      expect(described_class.adapter_for("ollama")).to be_a(Embeddings::OllamaAdapter)
    end

    it "returns an OpenaiAdapter for 'openai'" do
      expect(described_class.adapter_for("openai")).to be_a(Embeddings::OpenaiAdapter)
    end

    it "returns a GeminiAdapter for 'gemini'" do
      expect(described_class.adapter_for("gemini")).to be_a(Embeddings::GeminiAdapter)
    end

    it "raises for unknown providers" do
      expect { described_class.adapter_for("unknown") }.to raise_error(ArgumentError, /Unknown embedding provider/)
    end
  end

  describe ".current" do
    it "returns nil when embeddings are disabled" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_ENABLED").and_return("false")

      expect(described_class.current).to be_nil
    end

    it "returns the adapter for the configured provider" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_ENABLED").and_return(nil)
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_PROVIDER").and_return("gemini")

      expect(described_class.current).to be_a(Embeddings::GeminiAdapter)
    end
  end

  describe ".configured_provider" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_ENABLED").and_return(nil)
    end

    it "returns explicit env provider when set" do
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_PROVIDER").and_return("gemini")
      expect(described_class.configured_provider).to eq("gemini")
    end

    it "ignores unknown explicit providers" do
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_PROVIDER").and_return("bogus")
      allow(Rails.application.config).to receive(:try).with(:memory_embedding_provider).and_return(nil)
      # Auto-detect will try providers; stub them all as unhealthy
      allow_any_instance_of(Embeddings::OllamaAdapter).to receive(:healthy?).and_return(false)
      allow_any_instance_of(Embeddings::OpenaiAdapter).to receive(:healthy?).and_return(false)
      allow_any_instance_of(Embeddings::GeminiAdapter).to receive(:healthy?).and_return(false)

      expect(described_class.configured_provider).to be_nil
    end

    it "auto-detects ollama when reachable" do
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_PROVIDER").and_return(nil)
      allow(Rails.application.config).to receive(:try).with(:memory_embedding_provider).and_return(nil)
      allow_any_instance_of(Embeddings::OllamaAdapter).to receive(:healthy?).and_return(true)

      expect(described_class.configured_provider).to eq("ollama")
    end

    it "falls back to gemini when ollama and openai are unavailable" do
      allow(ENV).to receive(:[]).with("MEMORY_EMBEDDINGS_PROVIDER").and_return(nil)
      allow(Rails.application.config).to receive(:try).with(:memory_embedding_provider).and_return(nil)
      allow_any_instance_of(Embeddings::OllamaAdapter).to receive(:healthy?).and_return(false)
      allow_any_instance_of(Embeddings::OpenaiAdapter).to receive(:healthy?).and_return(false)
      allow_any_instance_of(Embeddings::GeminiAdapter).to receive(:healthy?).and_return(true)

      expect(described_class.configured_provider).to eq("gemini")
    end
  end

  describe ".available" do
    it "returns a list of all registered providers" do
      allow_any_instance_of(Embeddings::OllamaAdapter).to receive(:healthy?).and_return(true)
      allow_any_instance_of(Embeddings::OpenaiAdapter).to receive(:healthy?).and_return(false)
      allow_any_instance_of(Embeddings::GeminiAdapter).to receive(:healthy?).and_return(false)

      result = described_class.available
      expect(result.length).to eq(3)

      names = result.map { |r| r[:name] }
      expect(names).to contain_exactly("ollama", "openai", "gemini")

      ollama = result.find { |r| r[:name] == "ollama" }
      expect(ollama[:configured]).to be true
      expect(ollama[:cost]).to be_nil

      gemini = result.find { |r| r[:name] == "gemini" }
      expect(gemini[:configured]).to be false
      expect(gemini[:cost]).to eq(0.10)
    end
  end
end
