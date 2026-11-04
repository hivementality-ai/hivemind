# frozen_string_literal: true

module Tools
  # Answers +use_tool+: runs one of the agent's connector or MCP tools through
  # Tools::Executor, exactly as if the model had called it directly.
  class UseToolExecutor < BaseExecutor
    def call
      name = input["name"].to_s.strip
      pool = Tools::Search.pool(agent)
      tool = pool.find { |candidate| candidate.name == name }
      return unknown_tool(pool, name) unless tool

      arguments = input["arguments"]
      arguments = {} unless arguments.is_a?(Hash)
      Tools::Executor.call(tool: tool, input: arguments, agent: agent, session: config[:session])
    end

    private

    def unknown_tool(pool, name)
      close = Tools::Search.suggestions(pool, name)
      hint = close.any? ? " Close matches: #{close.join(', ')}." : " Use find_tools to search."
      ServiceResponse.failure(error: "Unknown tool '#{name}'.#{hint}")
    end
  end
end
