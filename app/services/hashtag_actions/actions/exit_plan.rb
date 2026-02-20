# frozen_string_literal: true

module HashtagActions
  module Actions
    class ExitPlan < Base
      def execute
        # Exit plan mode when #exit is used
        plan_tool = Tool.find_by(name: "plan_mode")
        unless plan_tool
          return { response: "Plan mode tool not found", bypass: false, status: "error" }
        end

        result = Tools::Executor.call(
          tool: plan_tool,
          input: { action: "exit" },
          agent: agent,
          session: session
        )

        if result.success?
          summary = result.data[:summary]
          markdown = result.data[:markdown]

          # Format response with summary and save options
          response = build_response(summary)

          {
            response: response,
            bypass: false,
            status: "ok",
            metadata: {
              summary: summary,
              markdown: markdown,
              session_id: session.id
            }
          }
        else
          { response: "Failed to exit plan mode: #{result.error}", bypass: false, status: "error" }
        end
      rescue StandardError => e
        Rails.logger.error("[ExitPlan Action] Error: #{e.message}")
        { response: "Exit plan error: #{e.message}", bypass: false, status: "error" }
      end

      private

      def build_response(summary)
        task = summary["original_task"]
        completed = summary["phases_completed"]
        total = summary["total_phases"]
        duration = summary["duration"]
        
        response_lines = []
        response_lines << "## ✅ Plan Execution Complete"
        response_lines << ""
        response_lines << "**Task:** #{task}"
        response_lines << "**Progress:** #{completed}/#{total} phases completed"
        response_lines << "**Duration:** #{duration}"
        response_lines << ""
        
        if summary["key_results"]&.any?
          response_lines << "### Key Results"
          summary["key_results"].each do |result|
            response_lines << "- #{result}"
          end
          response_lines << ""
        end
        
        response_lines << "### Plan Summary Options"
        response_lines << "You can now:"
        response_lines << "- 📥 Download summary as markdown"
        response_lines << "- 💾 Save to workspace (/workspace/plans/)"
        response_lines << "- 📋 Copy summary to clipboard"
        response_lines << ""
        response_lines << "*Click the \"Save Plan Summary\" button below to get started.*"
        
        response_lines.join("\n")
      end
    end
  end
end
