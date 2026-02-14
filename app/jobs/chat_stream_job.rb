# frozen_string_literal: true

class ChatStreamJob < ApplicationJob
  queue_as :default

  def perform(session_id, user_message)
    session = Session.find(session_id)
    agent = session.agent
    channel = "session_#{session.id}"

    # Append user message to transcript
    session.transcript << { "role" => "user", "content" => user_message, "timestamp" => Time.current.iso8601 }
    session.save!

    # Broadcast that user message was received
    ActionCable.server.broadcast(channel, { type: "user_message", content: user_message })

    # Resolve provider
    resolver = Providers::Resolver.call(provider_name: agent.model_provider, agent:)
    unless resolver.success?
      ActionCable.server.broadcast(channel, { type: "error", content: resolver.error })
      return
    end

    adapter = resolver.data[:adapter]

    # Build messages for LLM
    messages = build_messages(session:, agent:)

    # Resolve tools for this agent
    tools = resolve_tools(agent)

    begin
      # Use tool loop if agent has tools, otherwise simple chat
      if tools.any?
        result = Agents::ToolLoop.call(
          adapter:,
          agent:,
          session:,
          messages:,
          tools:,
          channel:,
          options: { model: agent.llm_model, max_tokens: 8192 }
        )
        full_content = result&.data&.dig(:content).to_s
      else
        # Simple chat (no tools)
        full_content = +""
        result = adapter.chat(
          messages:,
          options: { model: agent.llm_model, max_tokens: 8192 }
        ) do |chunk|
          if chunk[:type] == "content" && chunk[:content]
            full_content << chunk[:content]
            ActionCable.server.broadcast(channel, { type: "token", content: chunk[:content] })
          end
        end

        # If adapter doesn't support streaming, use sync result
        if full_content.empty? && result&.success?
          full_content = result.data[:content].to_s
          ActionCable.server.broadcast(channel, { type: "token", content: full_content })
        end
      end

      # Append assistant response to transcript
      session.reload
      session.transcript << { "role" => "assistant", "content" => full_content, "timestamp" => Time.current.iso8601 }
      session.save!

      # Track usage
      usage = result&.data&.dig(:usage) || {}
      track_usage(agent:, session:, usage:)

      # Store memory
      store_memory(agent:, session:, user_message:, assistant_response: full_content)

      ActionCable.server.broadcast(channel, { type: "done", content: full_content })

    rescue StandardError => e
      ActionCable.server.broadcast(channel, { type: "error", content: "Error: #{e.message}" })
      Rails.logger.error("ChatStreamJob error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end
  end

  private

  def resolve_tools(agent)
    # Get tools assigned to agent, or all enabled tools if none assigned
    assigned = agent.agent_tools.includes(:tool).map(&:tool).select(&:enabled?)
    return assigned if assigned.any?

    # Fall back to all enabled builtin tools
    Tool.enabled.builtin.to_a
  end

  def build_messages(session:, agent:)
    messages = []

    # System prompt
    system_prompt = agent.full_system_prompt.presence || "You are #{agent.name}, a helpful AI assistant."

    # Recall memories
    memory_context = recall_memories(agent:, session:)
    if memory_context.present?
      system_prompt += "\n\n## Relevant Memories\n#{memory_context}\n\nUse these memories naturally when relevant. Don't mention you're recalling memories."
    end

    messages << { role: "system", content: system_prompt }

    # Add transcript history (last 50 messages)
    session.transcript.last(50).each do |msg|
      messages << { role: msg["role"], content: msg["content"] }
    end

    messages
  end

  def recall_memories(agent:, session:)
    last_user_msg = session.transcript.select { |m| m["role"] == "user" }.last
    return nil unless last_user_msg

    query = last_user_msg["content"].to_s
    return nil if query.length < 5

    # Keyword search
    keywords = query.downcase.split(/\s+/).reject { |w| w.length < 4 }.first(5)
    return nil if keywords.empty?

    memories = keywords.flat_map do |kw|
      MemoryEntry.where(agent:)
                 .where("LOWER(content) LIKE ?", "%#{MemoryEntry.sanitize_sql_like(kw)}%")
                 .order(created_at: :desc)
                 .limit(3)
                 .to_a
    end

    recent = MemoryEntry.where(agent:).order(created_at: :desc).limit(3).to_a
    all_memories = (memories + recent).uniq(&:id).first(5)

    return nil if all_memories.empty?

    all_memories.map { |m| "- #{m.content.truncate(200)}" }.join("\n")
  end

  def track_usage(agent:, session:, usage:)
    return if usage.blank?

    input_tokens = usage[:input_tokens] || 0
    output_tokens = usage[:output_tokens] || 0
    cost = estimate_cost(agent.llm_model, input_tokens, output_tokens)

    UsageRecord.create(
      agent:,
      session:,
      llm_model: agent.llm_model,
      input_tokens:,
      output_tokens:,
      cost_cents: cost
    )
  end

  def estimate_cost(model, input_tokens, output_tokens)
    rates = {
      "gpt-4.1" => [200, 800],
      "gpt-4.1-mini" => [40, 160],
      "gpt-4.1-nano" => [10, 40],
      "claude-opus-4" => [1500, 7500],
      "claude-sonnet-4-5" => [300, 1500],
      "claude-haiku-4-5" => [80, 400]
    }
    input_rate, output_rate = rates[model] || [100, 300]
    ((input_tokens * input_rate + output_tokens * output_rate) / 1_000_000.0).round(4)
  end

  def store_memory(agent:, session:, user_message:, assistant_response:)
    return if user_message.length < 20

    MemoryEntry.create(
      agent:,
      content: "User asked: #{user_message.truncate(200)}\nAssistant: #{assistant_response.truncate(300)}",
      source: session,
      metadata: { session_id: session.id, stored_at: Time.current.iso8601 }
    )
  rescue StandardError => e
    Rails.logger.warn("Memory store failed: #{e.message}")
  end
end
