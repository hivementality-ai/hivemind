# frozen_string_literal: true

module Agents
  class ContextManager
    MODEL_LIMITS = {
      "claude-haiku-4-5" => 200_000,
      "claude-sonnet-4-5" => 200_000,
      "claude-opus-4-6" => 200_000,
      "gpt-5.2" => 200_000,
      "gpt-5.2-mini" => 200_000,
      "gpt-5.2-nano" => 128_000,
      "o3" => 200_000,
      "o4-mini" => 200_000
    }.freeze

    MAX_SYSTEM_TOKENS = 2000
    RESERVE_TOKENS = 1000      # Reserve for response
    TOKENS_PER_CHAR = 0.25     # Rough estimate: 4 chars per token

    def initialize(llm_model, max_output_tokens = 8192)
      @model = llm_model
      @max_output = max_output_tokens
      limit = MODEL_LIMITS[@model] || 200_000
      @budget = limit - @max_output - RESERVE_TOKENS
    end

    # Prune messages to stay within budget, keeping most recent messages
    def prune_messages(messages)
      return messages if messages.blank?

      system_msg = messages.find { |m| (m[:role] || m["role"])&.to_s == "system" }
      chat_msgs = messages.reject { |m| (m[:role] || m["role"])&.to_s == "system" }

      used_tokens = estimate_tokens(system_msg)
      pruned = [ system_msg ].compact
      messages_to_keep = []

      # Add messages from newest backwards
      chat_msgs.reverse_each do |msg|
        msg_tokens = estimate_tokens(msg)
        if used_tokens + msg_tokens > @budget
          Rails.logger.warn("ContextManager: pruning messages, budget exceeded. Used: #{used_tokens}, Limit: #{@budget}")
          break
        end
        used_tokens += msg_tokens
        messages_to_keep.unshift(msg)  # unshift to maintain reverse order
      end

      pruned.concat(messages_to_keep)

      if pruned.size < messages.size
        Rails.logger.info("ContextManager: pruned #{messages.size - pruned.size} messages (kept #{pruned.size})")
      end

      pruned
    end

    # Estimate token count for a single message
    def estimate_tokens(message)
      return 0 if message.blank?

      m = message.to_h.with_indifferent_access
      content = m[:content] || m["content"]

      # Calculate tokens
      case content
      when Array
        # Multimodal content (images + text)
        text_tokens = 0
        image_count = 0
        content.each do |block|
          case block[:type] || block["type"]
          when "text"
            text_tokens += (block[:text] || block["text"]).to_s.length * TOKENS_PER_CHAR
          when "image"
            image_count += 1
          end
        end
        # ~600 tokens per image (rough estimate)
        text_tokens.to_i + (image_count * 600) + 20
      else
        content.to_s.length * TOKENS_PER_CHAR + 10
      end.to_i
    end

    # Log budget info for debugging
    def budget_info
      {
        model: @model,
        limit: MODEL_LIMITS[@model],
        reserved_for_output: @max_output,
        reserved_for_safety: RESERVE_TOKENS,
        available_for_context: @budget
      }
    end
  end
end
