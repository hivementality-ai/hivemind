# frozen_string_literal: true

module Tools
  # Answers +find_tools+: searches the agent's connector and MCP tools and returns
  # each match with its input schema.
  class FindToolsExecutor < BaseExecutor
    def call
      query = input["query"].to_s.strip
      return ServiceResponse.failure(error: "Provide a query describing the tool you need") if query.empty?

      limit = input["limit"].to_i
      limit = Tools::Search::DEFAULT_LIMIT unless limit.positive?
      matches = Tools::Search.rank(Tools::Search.pool(agent), query, limit: limit)
      return ServiceResponse.success(data: { output: "No tools match '#{query}'. Try different keywords." }) if matches.empty?

      ServiceResponse.success(data: { output: matches.map { |tool| describe(tool) }.to_json })
    end

    private

    def describe(tool)
      {
        name: tool.name,
        description: tool.description.to_s.lines.first.to_s.strip,
        input_schema: tool.to_llm_tool[:input_schema]
      }
    end
  end
end
