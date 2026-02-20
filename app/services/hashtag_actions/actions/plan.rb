# frozen_string_literal: true

module HashtagActions
  module Actions
    class Plan < Base
      def execute
        # Enter planning mode when #plan is used
        
        # Invoke the plan_mode tool to enter planning mode
        plan_tool = Tool.find_by(name: "plan_mode")
        unless plan_tool
          return { response: "Planning mode tool not found", bypass: false, status: "error" }
        end

        result = Tools::Executor.call(
          tool: plan_tool,
          input: { action: "enter" },
          agent: agent,
          session: session
        )

        if result.success?
          # Broadcast planning mode activation
          ActionCable.server.broadcast(
            "session_#{session.id}",
            {
              type: "planning_mode",
              planning: true,
              message: "🧠 Planning mode activated..."
            }
          )

          {
            response: "Planning mode activated. Tool calls will be shown for planning context.",
            bypass: false,  # Don't bypass LLM — agent continues with the rest of the message
            status: "ok",
            prompt_addon: "User has activated planning mode. Show all tool calls and thinking steps for transparency."
          }
        else
          { response: "Failed to enter planning mode", bypass: false, status: "error" }
        end
      rescue StandardError => e
        Rails.logger.error("[Plan Action] Error: #{e.message}")
        { response: "Planning mode error: #{e.message}", bypass: false, status: "error" }
      end
    end
  end
end
