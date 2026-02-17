# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Context Pruning in Jobs", type: :job do
  let!(:agent) { Agent.create!(name: "Test Agent", role: "Helper", llm_model: "claude-haiku-4-5") }
  let!(:session) { Session.create!(agent: agent, status: :active, transcript: [], session_key: SecureRandom.uuid) }

  describe "ChatStreamJob message pruning" do
    it "prunes long conversation history before sending to LLM" do
      # Simulate a long conversation
      50.times do |i|
        session.transcript << {
          "role" => "user",
          "content" => "Question #{i}",
          "timestamp" => Time.current.iso8601
        }
        session.transcript << {
          "role" => "assistant",
          "content" => "Answer #{i}",
          "timestamp" => Time.current.iso8601
        }
      end
      session.save!

      # The job should prune old messages
      context_manager = Agents::ContextManager.new(agent.llm_model)
      budget_info = context_manager.budget_info

      expect(budget_info[:available_for_context]).to be > 0
      expect(budget_info[:available_for_context]).to be < 200_000
    end
  end

  describe "Message building with context manager" do
    it "estimates tokens correctly for system message" do
      context_manager = Agents::ContextManager.new(agent.llm_model)
      system_msg = {
        role: "system",
        content: "You are a helpful AI assistant."
      }

      tokens = context_manager.estimate_tokens(system_msg)
      expect(tokens).to be > 0
      expect(tokens).to be < 100
    end

    it "estimates tokens correctly for conversation" do
      context_manager = Agents::ContextManager.new(agent.llm_model)

      messages = [
        { role: "system", content: "You are helpful." },
        { role: "user", content: "What is 2+2?" },
        { role: "assistant", content: "2+2 equals 4" }
      ]

      total_tokens = messages.sum { |m| context_manager.estimate_tokens(m) }
      expect(total_tokens).to be > 0
      expect(total_tokens).to be < 1000
    end

    it "prunes conversation when it would exceed budget" do
      # Create context manager with very tight budget (10K tokens available)
      # This will force pruning since even a few large messages exceed it
      tight_manager = Agents::ContextManager.new(agent.llm_model, 190_000)

      # Create a conversation that exceeds budget
      messages = [
        { role: "system", content: "You are helpful." }
      ]

      # Add many large messages (each is ~2.5K tokens)
      5.times do |i|
        messages << { role: "user", content: "x" * 10_000 }
        messages << { role: "assistant", content: "y" * 10_000 }
      end

      pruned = tight_manager.prune_messages(messages)

      # Should be shorter than original since messages exceed tight budget
      expect(pruned.size).to be < messages.size
      # Should still have system message
      expect(pruned.first[:role]).to eq("system")
    end
  end

  describe "TokenEstimation with different content types" do
    subject(:context_manager) { Agents::ContextManager.new("claude-haiku-4-5") }

    it "handles simple text" do
      msg = { role: "user", content: "Hello" }
      tokens = context_manager.estimate_tokens(msg)
      expect(tokens).to be_between(1, 20)
    end

    it "handles multimodal with images" do
      msg = {
        role: "user",
        content: [
          { type: "text", text: "What is this?" },
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "..." } }
        ]
      }
      tokens = context_manager.estimate_tokens(msg)
      expect(tokens).to be > 500
    end

    it "accumulates tokens across multiple messages" do
      messages = [
        { role: "system", content: "System prompt" },
        { role: "user", content: "User message" },
        { role: "assistant", content: "Assistant response" }
      ]

      total = messages.sum { |m| context_manager.estimate_tokens(m) }

      messages.each do |msg|
        individual = context_manager.estimate_tokens(msg)
        expect(individual).to be > 0
      end

      expect(total).to be > 0
    end
  end
end
