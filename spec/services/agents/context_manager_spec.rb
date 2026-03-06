# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ContextManager, type: :service do
  describe "initialization" do
    it "sets budget based on model" do
      manager = described_class.new("claude-haiku-4-5")
      budget = manager.budget_info[:available_for_context]

      expect(budget).to be > 0
      expect(budget).to be < 200_000 # Leave room for output + reserve
    end

    it "handles unknown models gracefully" do
      manager = described_class.new("unknown-model")
      expect(manager.budget_info[:available_for_context]).to be > 0
    end

    it "uses correct limits for Ollama models in MODEL_LIMITS" do
      manager = described_class.new("qwen3-coder:30b", 4096)
      # 32_768 - 4096 - 1000 = 27_672
      expect(manager.budget_info[:available_for_context]).to eq(27_672)
    end

    it "defaults unknown Ollama models to 131K context" do
      manager = described_class.new("some-local-model", 2048, provider: "ollama")
      # 131_072 - 2048 - 1000 = 128_024
      expect(manager.budget_info[:available_for_context]).to eq(128_024)
    end

    it "defaults unknown models without provider to 200K context" do
      manager = described_class.new("unknown-cloud-model", 8192)
      # 200_000 - 8192 - 1000 = 190_808
      expect(manager.budget_info[:available_for_context]).to eq(190_808)
    end
  end

  describe "#estimate_tokens" do
    subject(:manager) { described_class.new("claude-haiku-4-5") }

    it "estimates tokens for simple text message" do
      message = { role: "user", content: "Hello, how are you?" }
      tokens = manager.estimate_tokens(message)

      expect(tokens).to be > 0
      expect(tokens).to be < 50
    end

    it "estimates tokens for longer text" do
      long_text = "Hello world " * 100  # ~1200 chars
      message = { role: "assistant", content: long_text }
      tokens = manager.estimate_tokens(message)

      expect(tokens).to be > 100
      expect(tokens).to be < 500
    end

    it "estimates tokens for multimodal content (text + images)" do
      message = {
        role: "user",
        content: [
          { type: "text", text: "What's in this image?" },
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "..." } },
          { type: "image", source: { type: "base64", media_type: "image/png", data: "..." } }
        ]
      }
      tokens = manager.estimate_tokens(message)

      # ~4 chars / token for text + ~600 tokens per image
      expect(tokens).to be > 1000
      expect(tokens).to be < 1500
    end

    it "handles nil message gracefully" do
      expect(manager.estimate_tokens(nil)).to eq(0)
    end

    it "handles empty content" do
      message = { role: "user", content: "" }
      tokens = manager.estimate_tokens(message)
      expect(tokens).to be >= 0
    end
  end

  describe "#prune_messages" do
    subject(:manager) { described_class.new("claude-haiku-4-5", 8192) }

    it "returns all messages if they fit in budget" do
      messages = [
        { role: "system", content: "You are helpful." },
        { role: "user", content: "Short question?" },
        { role: "assistant", content: "Short answer." }
      ]

      pruned = manager.prune_messages(messages)
      expect(pruned).to eq(messages)
    end

    it "keeps system message even if budget exceeded" do
      system_msg = { role: "system", content: "You are helpful." }
      messages = [
        system_msg,
        { role: "user", content: "x" * 50_000 },
        { role: "assistant", content: "y" * 50_000 }
      ]

      pruned = manager.prune_messages(messages)
      expect(pruned.first).to eq(system_msg)
    end

    it "prunes oldest chat messages when budget exceeded" do
      # llama3.2 has 8_192 limit. Budget = [8192 - 4096 - 1000, 8192/2].max = 4096
      tight_budget_manager = described_class.new("llama3.2", 4_096)

      messages = [
        { role: "system", content: "You are helpful." },
        { role: "user", content: "Old question" },
        { role: "assistant", content: "Old answer" },
        { role: "user", content: "x" * 12_000 },  # ~3K tokens
        { role: "assistant", content: "y" * 12_000 }  # ~3K tokens
      ]

      pruned = tight_budget_manager.prune_messages(messages)

      # Should keep system message
      expect(pruned.first[:role]).to eq("system")
      # Recent messages that fit in budget should be kept
      expect(pruned.any? { |m| m[:content].include?("x") || m[:content].include?("y") }).to be true
      # But earlier messages may be dropped
      expect(pruned.size).to be <= messages.size
      # Importantly, not all messages fit
      expect(pruned.size).to be < messages.size
    end

    it "keeps most recent messages" do
      messages = [
        { role: "system", content: "You are helpful." },
        { role: "user", content: "Old message 1" },
        { role: "assistant", content: "Old answer 1" },
        { role: "user", content: "Recent message 2" },
        { role: "assistant", content: "Recent answer 2" }
      ]

      pruned = manager.prune_messages(messages)

      # Recent messages should be present
      expect(pruned.map { |m| m[:content] }).to include("Recent message 2")
      expect(pruned.map { |m| m[:content] }).to include("Recent answer 2")
    end

    it "handles messages with indifferent access (symbol/string keys)" do
      messages = [
        { "role" => "system", "content" => "You are helpful." },
        { role: "user", content: "Question?" },
        { "role" => "assistant", "content" => "Answer." }
      ]

      pruned = manager.prune_messages(messages)
      expect(pruned).not_to be_empty
    end

    it "returns empty array for empty input" do
      expect(manager.prune_messages([])).to eq([])
    end

    it "returns nil for nil input" do
      expect(manager.prune_messages(nil)).to be_nil
    end
  end

  describe "#budget_info" do
    it "returns budget breakdown" do
      manager = described_class.new("claude-sonnet-4-5", 8192)
      info = manager.budget_info

      expect(info).to include(:model, :limit, :reserved_for_output, :reserved_for_safety, :available_for_context)
      expect(info[:model]).to eq("claude-sonnet-4-5")
      expect(info[:reserved_for_output]).to eq(8192)
      expect(info[:reserved_for_safety]).to eq(1000)
    end
  end

  describe "multimodal content handling" do
    subject(:manager) { described_class.new("claude-haiku-4-5") }

    it "estimates tokens for mixed multimodal content" do
      message = {
        role: "user",
        content: [
          { type: "text", text: "What's in this?" },
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "base64..." } }
        ]
      }

      tokens = manager.estimate_tokens(message)
      expect(tokens).to be > 600  # At least one image's worth
    end

    it "counts multiple images correctly" do
      message = {
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "img1" } },
          { type: "image", source: { type: "base64", media_type: "image/png", data: "img2" } },
          { type: "image", source: { type: "base64", media_type: "image/webp", data: "img3" } }
        ]
      }

      tokens = manager.estimate_tokens(message)
      expect(tokens).to be >= 1800  # ~600 per image
    end
  end
end
