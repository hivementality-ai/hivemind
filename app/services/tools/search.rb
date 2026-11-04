# frozen_string_literal: true

module Tools
  # Decides how an agent's connector and MCP tools are offered to the model. Up to
  # the threshold they are listed as they are; above it the model gets only
  # +find_tools+ and +use_tool+ and looks the rest up on demand.
  module Search
    THRESHOLD_KEY = "tool_search_threshold"
    DEFAULT_THRESHOLD = 20
    DEFAULT_LIMIT = 8
    MAX_SUGGESTIONS = 5

    class << self
      # @return [Array<#to_llm_tool>] the connector and MCP tools to add to a request's tool list
      def offered(agent)
        pool = pool(agent)
        return pool unless pool.size > threshold

        [ SystemTool::FIND_TOOLS, SystemTool::USE_TOOL ]
      end

      # @return [Array<#to_llm_tool>] every connector and MCP tool the agent can call
      def pool(agent)
        Mcp::ToolResolver.proxies(agent) + Connectors::ToolResolver.proxies(agent)
      end

      # @return [Integer] how many connector and MCP tools may be listed directly
      def threshold
        Integer(Setting.get(THRESHOLD_KEY).presence || DEFAULT_THRESHOLD)
      rescue ArgumentError, TypeError
        DEFAULT_THRESHOLD
      end

      # Ranks tools by keyword matches on name, description and connector name.
      #
      # @return [Array<#to_llm_tool>] the best matches, best first
      def rank(pool, query, limit: DEFAULT_LIMIT)
        terms = tokens(query)
        return [] if terms.empty?

        scored = pool.filter_map do |tool|
          score = score(tool, terms)
          [ tool, score ] if score.positive?
        end
        scored.sort_by { |tool, score| [ -score, tool.name ] }.first(limit).map(&:first)
      end

      # @return [Array<String>] names closest to +name+, for "did you mean" errors
      def suggestions(pool, name)
        rank(pool, name.to_s.tr("_", " "), limit: MAX_SUGGESTIONS).map(&:name)
      end

      private

      def score(tool, terms)
        name_tokens = tokens(tool.name)
        name = tool.name.to_s.downcase
        owner = tokens(tool.try(:connector_name))
        description = tokens(tool.description)

        terms.sum do |term|
          (name_tokens.include?(term) ? 4 : 0) + (name.include?(term) ? 2 : 0) +
            (owner.include?(term) ? 3 : 0) + (description.include?(term) ? 1 : 0)
        end
      end

      def tokens(text)
        text.to_s.downcase.split(/[^a-z0-9]+/).reject(&:empty?).uniq
      end
    end
  end
end
