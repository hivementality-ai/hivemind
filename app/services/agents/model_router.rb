# frozen_string_literal: true

module Agents
  # Routes tasks to appropriate model tiers based on the last user message
  # and recent tool activity. Ports rubyn-code's LLM::ModelRouter.
  #
  # Auto-routing is only enabled for the two "big" providers (Anthropic,
  # OpenAI). Everything else (Ollama, openai_compatible) keeps the agent's
  # pinned model. When an agent's llm_model == "auto", ChatStreamJob calls
  # `route` to pick a model for this turn; otherwise the pinned model is
  # used verbatim.
  #
  # Defaults are baked in; fine-tuning is read from the Setting row
  # `model_router_rules` as a JSON blob of the same shape as DEFAULT_RULES.
  module ModelRouter
    AUTO_SUPPORTED_PROVIDERS = %w[anthropic openai].freeze

    # Tiers x providers -> concrete model IDs.
    DEFAULT_RULES = {
      "anthropic" => {
        "tiers" => {
          "cheap" => "claude-haiku-4-5",
          "mid"   => "claude-sonnet-4-6",
          "top"   => "claude-opus-4-6"
        },
        "fallback_tier" => "mid"
      },
      "openai" => {
        "tiers" => {
          "cheap" => "gpt-5.4-nano",
          "mid"   => "gpt-5.4-mini",
          "top"   => "gpt-5.4"
        },
        "fallback_tier" => "mid"
      }
    }.freeze

    TASK_TIERS = {
      "cheap" => %w[file_search format_code git_operations memory_retrieval context_summary chatting explore],
      "mid"   => %w[generate_specs simple_refactor code_review documentation bug_fix],
      "top"   => %w[architecture complex_refactor security_review performance planning]
    }.freeze

    MESSAGE_PATTERNS = [
      [ /\b(architect|design|restructure|multi.?file)\b/i, "architecture" ],
      [ /\b(security|vulnerab|audit|owasp)\b/i,            "security_review" ],
      [ /\b(n\+1|performance|slow|optimize|query)\b/i,     "performance" ],
      [ /\b(spec|test|rspec)\b/i,                          "generate_specs" ],
      [ /\b(fix|bug|error|broken)\b/i,                     "bug_fix" ],
      [ /\b(refactor|extract|rename|move)\b/i,             "simple_refactor" ],
      [ /\b(find|where|search|locate)\b/i,                 "file_search" ],
      [ /\b(doc|readme|comment|explain)\b/i,               "documentation" ]
    ].freeze

    TOOL_TASK_MAP = {
      "grep"       => "file_search",
      "glob"       => "file_search",
      "file_read"  => "file_search",
      "run_specs"  => "generate_specs",
      "review_pr"  => "code_review",
      "git_status" => "git_operations",
      "git_log"    => "git_operations",
      "git_diff"   => "git_operations",
      "git_commit" => "git_operations"
    }.freeze

    def self.auto_supported?(provider)
      AUTO_SUPPORTED_PROVIDERS.include?(provider.to_s)
    end

    # @param provider [String] "anthropic" or "openai"
    # @param message_text [String] the current user message
    # @param recent_tools [Array<String>] recent tool call names (most recent last)
    # @return [String] model ID to use for this turn
    def self.route(provider:, message_text:, recent_tools: [])
      return nil unless auto_supported?(provider)

      task = detect_task(message_text, recent_tools: recent_tools)
      tier = tier_for(task)

      rules = rules_for(provider)
      tier_model = rules.dig("tiers", tier)
      return tier_model if tier_model

      # Unknown tier in custom rules — fall back to DEFAULT_RULES for this provider.
      DEFAULT_RULES.dig(provider, "tiers", tier)
    end

    def self.detect_task(message_text, recent_tools: [])
      detect_from_message(message_text) || detect_from_tools(recent_tools) || "chatting"
    end

    def self.tier_for(task)
      TASK_TIERS.each do |tier, tasks|
        return tier if tasks.include?(task.to_s)
      end
      "mid"
    end

    # Merges DEFAULT_RULES with the Setting-backed override so operators
    # can tune tier model IDs, patterns, etc. without a redeploy.
    def self.rules_for(provider)
      custom = custom_rules[provider] || {}
      defaults = DEFAULT_RULES[provider] || {}
      deep_merge(defaults, custom)
    end

    def self.custom_rules
      raw = Setting.get("model_router_rules")
      return {} if raw.blank?
      JSON.parse(raw)
    rescue JSON::ParserError, StandardError => e
      Rails.logger.warn("[ModelRouter] custom rules unparseable, falling back to defaults: #{e.message}")
      {}
    end

    def self.detect_from_message(message_text)
      return nil if message_text.to_s.strip.empty?

      MESSAGE_PATTERNS.each do |pattern, task|
        return task if message_text.match?(pattern)
      end
      nil
    end

    def self.detect_from_tools(recent_tools)
      return nil if recent_tools.empty?
      TOOL_TASK_MAP[recent_tools.last.to_s]
    end

    def self.deep_merge(a, b)
      a.merge(b) { |_k, va, vb| va.is_a?(Hash) && vb.is_a?(Hash) ? deep_merge(va, vb) : vb }
    end
  end
end
