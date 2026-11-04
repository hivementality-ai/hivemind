# frozen_string_literal: true

module Tools
  class DelegateExecutor < BaseExecutor
    # Thin adapter over Delegations::Request — parses tool input, delegates,
    # formats the result for the LLM. All guardrails (team scoping, depth,
    # fan-out, dedup) live in Delegations::Request.
    def call
      result = Delegations::Request.call(
        from_agent: agent,
        from_session: config[:session],
        target_name: input["agent"],
        task: input["task"]
      )
      return result unless result.success?

      target = result.data[:target]
      task_key = result.data[:task_key]

      ServiceResponse.success(data: {
        output: "Delegated to #{target.name}: #{input['task'].to_s.strip.truncate(200)}\nTask ID: #{task_key}\n\n#{target.name} is now working on this in their own session. Use delegation_status with this task ID to check progress. They will report back when done.",
        exit_code: 0
      })
    end
  end
end
