# frozen_string_literal: true

module HashtagActions
  module Actions
    class Plan < Base
      def execute
        # Extract task from payload if provided, otherwise use the clean message
        task = if payload.present?
                 payload.strip
               else
                 clean_message&.strip.presence || "General task planning"
               end

        # Invoke the plan_mode tool to generate a plan
        plan_tool = Tool.find_by(name: "plan_mode")
        unless plan_tool
          return { response: "Planning mode tool not found", bypass: false, status: "error" }
        end

        Rails.logger.info("[Plan Action] Invoking plan_mode with action=generate, task=#{task.inspect}, agent=#{agent&.name}, session=#{session&.id}")
        
        result = Tools::Executor.call(
          tool: plan_tool,
          input: { "action" => "generate", "task" => task },
          agent: agent,
          session: session
        )
        
        Rails.logger.info("[Plan Action] Result: #{result.inspect}")

        if result.success?
          # Get the plan from session metadata (it was saved there by the executor)
          plan = session.reload.metadata&.dig("current_plan")
          
          if plan
            # Provide phase context in prompt addon so agent knows the plan
            phase_context = build_phase_context(plan)

            {
              response: nil,  # Plan card already saved to transcript by executor
              bypass: true,   # Don't call LLM
              status: "ok"
            }
          else
            { response: "Plan generated but couldn't retrieve it from session", bypass: false, status: "error" }
          end
        else
          { response: "Failed to generate plan: #{result.error}", bypass: false, status: "error" }
        end
      rescue StandardError => e
        Rails.logger.error("[Plan Action] Error: #{e.message}")
        { response: "Planning error: #{e.message}", bypass: false, status: "error" }
      end

      private

      def format_plan_for_display(plan)
        lines = []
        lines << "## 📋 Work Plan"
        lines << ""
        lines << "> #{plan['overview']}"
        lines << ""
        lines << "---"
        lines << ""
        
        plan["phases"].each do |phase|
          lines << "### Phase #{phase['number']}: #{phase['name']}"
          lines << ""
          phase["objectives"].each do |obj|
            lines << "- #{obj}"
          end
          lines << ""
          lines << "*Approach:* #{phase['approach']}"
          lines << ""
        end
        
        lines << "---"
        lines << ""
        lines << "**✅ Success Criteria**"
        plan["success_criteria"].each do |criteria|
          lines << "- #{criteria}"
        end
        lines << ""
        lines << "⏱️ *#{plan['estimated_duration']}*"
        
        lines.join("\n")
      end

      def build_phase_context(plan)
        phase_descriptions = plan["phases"].map do |phase|
          "Phase #{phase['number']} (#{phase['name']}): #{phase['objectives'].join('; ')}"
        end.join("\n")

        <<~CONTEXT
          User has created a multi-phase plan:
          #{phase_descriptions}

          You will execute this plan phase by phase:
          1. Start each phase with a clear marker: "## Phase N: [name]"
          2. Execute the objectives for the current phase
          3. Track your progress and show what you've accomplished
          4. When ready, move to the next phase
          
          You can reference the plan whenever needed to stay on track.
        CONTEXT
      end
    end
  end
end
