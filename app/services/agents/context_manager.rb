# frozen_string_literal: true

module Agents
  class ContextManager
    # Ollama models sized conservatively (RAM constrained). These are keyed by
    # the specific Ollama tag rather than a provider API ID, so they live here
    # rather than in LlmModelRegistry (which covers cloud-provider IDs only).
    OLLAMA_MODEL_LIMITS = {
      "qwen3-coder:30b"  => 32_768,
      "qwen3-coder"      => 32_768,
      "llama3.2"         => 8_192,
      "llama3.1"         => 8_192,
      "codellama"        => 16_384,
      "deepseek-coder-v2" => 16_384
    }.freeze

    MAX_SYSTEM_TOKENS = 2000
    RESERVE_TOKENS = 1000      # Reserve for response
    TOKENS_PER_CHAR = 0.25     # Rough estimate: 4 chars per token

    def initialize(llm_model, max_output_tokens = 8192, provider: nil, agent: nil)
      @model = llm_model
      @max_output = agent&.max_output_tokens || max_output_tokens
      @provider = provider
      limit = agent&.context_window || context_window_for_model || default_limit_for_provider
      @budget = [ limit - @max_output - RESERVE_TOKENS, limit / 2 ].max
    end

    # Prune messages to stay within budget, keeping most recent messages.
    # Four-stage pipeline: micro-compact (replace old tool results with
    # placeholders) → context-collapse (drop the middle) → auto-compact
    # (LLM summarization of the tail) → hard prune (oldest-first).
    def prune_messages(messages)
      return messages if messages.blank?

      working = messages.dup

      # Stage 1: micro-compact — only when we're nearing the budget, so we
      # don't mutate cached message prefixes every single turn.
      if estimate_tokens_for(working) > (@budget * 0.7)
        Agents::MicroCompact.call(working, keep_recent: 2)
      end

      # Stage 2: context-collapse — zero-LLM middle-snip before any
      # LLM summarization.
      if estimate_tokens_for(working) > @budget
        collapsed = Agents::ContextCollapse.call(working, threshold: @budget, keep_recent: 6)
        working = collapsed if collapsed
      end

      # Stage 3: auto-compact — LLM summarization of the full tail. Only
      # triggered if the zero-LLM stages above couldn't get us under budget.
      if estimate_tokens_for(working) > @budget
        compacted = compactor.auto_compact!(working)
        working = compacted if compacted.present?
      end

      # Stage 4: hard prune — last-resort oldest-first truncation if the
      # LLM call failed or no Anthropic provider is configured.
      hard_prune(working)
    end

    # Forced LLM summarization, bypassing thresholds. Called by ToolLoop
    # when the provider returns a prompt-too-long error and we need to
    # aggressively shrink the context before retrying.
    def force_auto_compact!(messages)
      compactor.auto_compact!(messages) || hard_prune(messages)
    end

    # User-triggered summarization with an optional focus prompt. Hashtag
    # action /compact wires through here.
    def manual_compact!(messages, focus: nil)
      compactor.manual_compact!(messages, focus: focus) || messages
    end

    def compactor
      @compactor ||= Agents::Compactor.new(agent: @agent, threshold: @budget)
    end

    # Shared token estimator used by DecisionCompactor and the pipeline.
    def estimate_tokens_for(messages)
      (messages || []).sum { |m| estimate_tokens(m) }
    end

    def hard_prune(messages)
      system_msg = messages.find { |m| (m[:role] || m["role"])&.to_s == "system" }
      chat_msgs = messages.reject { |m| (m[:role] || m["role"])&.to_s == "system" }

      used_tokens = estimate_tokens(system_msg)
      pruned = [ system_msg ].compact
      messages_to_keep = []

      chat_msgs.reverse_each do |msg|
        msg_tokens = estimate_tokens(msg)
        if used_tokens + msg_tokens > @budget
          Rails.logger.warn("ContextManager: pruning messages, budget exceeded. Used: #{used_tokens}, Limit: #{@budget}")
          break
        end
        used_tokens += msg_tokens
        messages_to_keep.unshift(msg)
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

    def default_limit_for_provider
      if %w[ollama openai_compatible].include?(@provider)
        # Ollama dynamically sizes num_ctx, so use a generous default.
        # The adapter will request the right context window from the server.
        131_072
      else
        200_000
      end
    end

    # Log budget info for debugging
    def budget_info
      {
        model: @model,
        limit: context_window_for_model,
        reserved_for_output: @max_output,
        reserved_for_safety: RESERVE_TOKENS,
        available_for_context: @budget
      }
    end

    private

    # Resolve context window: registry first (cloud models), then Ollama-specific
    # table for local models identified by tag (e.g. "qwen3-coder:30b").
    def context_window_for_model
      LlmModelRegistry.context_window(@model) || OLLAMA_MODEL_LIMITS[@model]
    end
  end
end
