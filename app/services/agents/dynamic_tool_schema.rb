# frozen_string_literal: true

module Agents
  # Filters tool schemas sent to the LLM based on the detected task context.
  # Anthropic tool schemas cost ~50-200 tokens each; filtering 20+ tools down
  # to the ~5-8 relevant to the current task cuts 1-3k tokens per turn.
  #
  # Defensive: if filtering would leave the agent with zero tools, we fall
  # back to the full list so the agent is never hobbled.
  #
  # Ported from rubyn-code's DynamicToolSchema, adapted for hivemind's
  # DB-backed Tool records (name + description pattern matching rather than a
  # hard-coded task → tool map).
  module DynamicToolSchema
    # Tools to always include, regardless of detected context.
    BASE_PATTERNS = %w[
      read_file write_file edit_file glob grep
      shell bash execute_command
    ].freeze

    # Keywords per task context. A tool matches if its name OR description
    # contains any of the keywords (case-insensitive, word boundary).
    TASK_PATTERNS = {
      testing: %w[spec rspec test],
      git:     %w[git commit diff branch merge push],
      review:  %w[review pr pull_request],
      rails:   %w[rails migrate generate scaffold bundle],
      web:     %w[web search fetch url http],
      memory:  %w[memory remember recall],
      tasks:   %w[task todo],
      teams:   %w[spawn team inbox message_agent],
      explore: %w[explore architecture structure]
    }.freeze

    class << self
      # Detect task context from a user message. Returns nil if no context
      # can be confidently inferred.
      def detect_context(message)
        msg = message.to_s.downcase
        return nil if msg.strip.empty?

        return :testing if msg.match?(/\b(tests?|specs?|rspec)\b/)
        return :git     if msg.match?(/\b(commits?|push|diff|branch|merge|git)\b/)
        return :review  if msg.match?(/\b(review|pr|pull request)\b/)
        return :rails   if msg.match?(/\b(migrat\w*|generate|scaffold|rails)\b/)
        return :web     if msg.match?(/\b(search|fetch|url|http|api)\b/)
        return :explore if msg.match?(/\b(explore|architecture|structure)\b/)
        return :teams   if msg.match?(/\b(teams?|spawn|inbox)\b/)

        nil
      end

      # Filter tools for the given context. If context is nil, returns the
      # tools unchanged.
      #
      # @param tools [Array<Tool>] tool records with #name and #description
      # @param context [Symbol, nil] result of detect_context
      # @param discovered_names [Array<String>] tools already used this session
      def filter(tools, context:, discovered_names: [])
        return tools if context.nil?
        return tools if tools.size <= 5

        keywords = TASK_PATTERNS[context] || []
        keyword_regex = build_keyword_regex(keywords)
        base_regex = build_keyword_regex(BASE_PATTERNS)
        discovered_set = discovered_names.to_set

        filtered = tools.select do |tool|
          name = tool.respond_to?(:name) ? tool.name.to_s : tool[:name].to_s
          description = tool.respond_to?(:description) ? tool.description.to_s : tool[:description].to_s
          haystack = "#{name} #{description}".downcase

          discovered_set.include?(name) ||
            (base_regex && haystack.match?(base_regex)) ||
            (keyword_regex && haystack.match?(keyword_regex))
        end

        filtered.empty? ? tools : filtered
      end

      private

      def build_keyword_regex(keywords)
        return nil if keywords.nil? || keywords.empty?
        escaped = keywords.map { |kw| Regexp.escape(kw.to_s.downcase) }
        /\b(#{escaped.join('|')})\b/
      end
    end
  end
end
