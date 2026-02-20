# frozen_string_literal: true

module Tools
  class PlanModeExecutor < BaseExecutor
    def call
      Rails.logger.info("[PlanModeExecutor] Full input: #{input.inspect}")
      Rails.logger.info("[PlanModeExecutor] Full config: #{config.inspect}")
      
      action = input["action"]&.downcase
      session = config[:session]

      Rails.logger.info("[PlanModeExecutor] Parsed action: #{action.inspect} (class: #{action.class}), session: #{session&.id}")

      case action
      when "generate"
        Rails.logger.info("[PlanModeExecutor] Executing generate_plan")
        generate_plan(session)
      when "execute"
        Rails.logger.info("[PlanModeExecutor] Executing start_execution")
        start_execution(session)
      when "update_phase"
        Rails.logger.info("[PlanModeExecutor] Executing update_execution_phase")
        update_execution_phase(session)
      when "exit"
        Rails.logger.info("[PlanModeExecutor] Executing exit_plan_mode")
        exit_plan_mode(session)
      else
        Rails.logger.error("[PlanModeExecutor] Invalid action: #{action.inspect} (expected one of: generate, execute, update_phase, exit)")
        ServiceResponse.failure(error: "Invalid action. Use 'generate', 'execute', 'update_phase', or 'exit'")
      end
    rescue StandardError => e
      Rails.logger.error("[PlanModeExecutor] Error: #{e.message}")
      ServiceResponse.failure(error: "Planning mode operation failed: #{e.message}")
    end

    private

    def generate_plan(session)
      task = input["task"]&.strip
      unless task.present?
        return ServiceResponse.failure(error: "Task is required for plan generation")
      end

      # Generate plan using the PlanGenerator service
      plan_result = Agents::PlanGenerator.call(
        agent: agent,
        task: task,
        session: session
      )

      unless plan_result.success?
        return ServiceResponse.failure(error: plan_result.error)
      end

      plan = plan_result.data[:plan]

      # Store plan in session metadata
      session.metadata ||= {}
      session.metadata["current_plan"] = plan
      session.metadata["plan_generated_at"] = Time.current.iso8601
      session.metadata["plan_status"] = "generated"
      session.metadata["current_phase"] = 0
      session.save!

      # Format plan for display in chat
      plan_message = format_plan_for_transcript(plan)

      # Save plan as assistant message in transcript so it persists
      session.append_transcript({
        "role" => "assistant",
        "content" => plan_message,
        "timestamp" => Time.current.iso8601,
        "type" => "plan",
        "plan_data" => plan
      })
      session.save!

      # Broadcast plan to UI
      ActionCable.server.broadcast(
        "session_#{session.id}",
        {
          type: "plan",
          action: "display",
          plan: plan,
          message: "📋 Plan generated. Ready to execute."
        }
      )

      output = "Plan generated with #{plan['phases'].length} phases. Ready to execute."
      ServiceResponse.success(data: { output: output, exit_code: 0, plan: plan })
    end

    def start_execution(session)
      plan = session.metadata&.dig("current_plan")
      unless plan.present?
        return ServiceResponse.failure(error: "No plan available. Generate a plan first.")
      end

      # Initialize execution tracking
      session.metadata ||= {}
      session.metadata["plan_status"] = "executing"
      session.metadata["current_phase"] = 1
      session.metadata["plan_started_at"] = Time.current.iso8601
      session.save!

      # Broadcast execution start
      ActionCable.server.broadcast(
        "session_#{session.id}",
        {
          type: "plan",
          action: "start_execution",
          current_phase: 1,
          total_phases: plan["phases"].length,
          message: "🚀 Plan execution started. Beginning Phase 1."
        }
      )

      output = "Plan execution started. Proceeding with Phase 1: #{plan['phases'][0]['name']}"
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def update_execution_phase(session)
      phase_number = input["phase_number"]
      unless phase_number.present?
        return ServiceResponse.failure(error: "phase_number is required")
      end

      plan = session.metadata&.dig("current_plan")
      unless plan.present?
        return ServiceResponse.failure(error: "No plan available")
      end

      # Validate phase number
      total_phases = plan["phases"].length
      if phase_number < 1 || phase_number > total_phases
        return ServiceResponse.failure(error: "Invalid phase number. Expected 1-#{total_phases}")
      end

      # Update current phase
      session.metadata ||= {}
      session.metadata["current_phase"] = phase_number
      session.save!

      # Broadcast phase update
      current_phase_data = plan["phases"][phase_number - 1]
      ActionCable.server.broadcast(
        "session_#{session.id}",
        {
          type: "plan",
          action: "phase_update",
          current_phase: phase_number,
          total_phases: total_phases,
          phase_data: current_phase_data,
          message: "📍 Moving to Phase #{phase_number}: #{current_phase_data['name']}"
        }
      )

      output = "Phase #{phase_number} started: #{current_phase_data['name']}"
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def exit_plan_mode(session)
      plan = session.metadata&.dig("current_plan")
      unless plan.present?
        return ServiceResponse.failure(error: "No active plan to exit")
      end

      # Generate summary
      summary_result = Agents::PlanSummaryGenerator.call(
        session: session,
        agent: agent
      )

      unless summary_result.success?
        return ServiceResponse.failure(error: summary_result.error)
      end

      summary_data = summary_result.data

      # Update session metadata - clear planning mode
      session.metadata ||= {}
      session.metadata["plan_status"] = "completed"
      session.metadata["plan_completed_at"] = Time.current.iso8601
      session.metadata["plan_summary"] = {
        "original_task" => summary_data[:summary]["original_task"],
        "phases_completed" => summary_data[:summary]["phases_completed"],
        "total_phases" => summary_data[:summary]["total_phases"],
        "duration" => summary_data[:summary]["duration"],
        "key_results" => summary_data[:summary]["key_results"],
        "learnings" => summary_data[:learnings]
      }
      session.save!

      # Broadcast plan exit with summary to UI
      ActionCable.server.broadcast(
        "session_#{session.id}",
        {
          type: "plan",
          action: "exit",
          summary: summary_data[:summary],
          markdown: summary_data[:markdown],
          learnings: summary_data[:learnings],
          message: "📋 Plan mode exited. Summary generated."
        }
      )

      output = "Plan mode exited. Session summary saved."
      ServiceResponse.success(data: {
        output: output,
        exit_code: 0,
        summary: summary_data[:summary],
        markdown: summary_data[:markdown]
      })
    end

    def format_plan_for_transcript(plan)
      lines = []
      lines << "📋 **Plan Generated**"
      lines << ""
      lines << "**Overview**: #{plan['overview']}"
      lines << "**Context**: #{plan['context']}"
      lines << ""
      lines << "**Phases**:"
      
      plan["phases"].each do |phase|
        lines << ""
        lines << "**Phase #{phase['number']}: #{phase['name']}**"
        lines << "  • Objectives: #{phase['objectives'].join('; ')}"
        lines << "  • Approach: #{phase['approach']}"
        lines << "  • Tools: #{phase['tools_needed'].join(', ')}"
        lines << "  • Expected Output: #{phase['expected_output']}"
      end
      
      lines << ""
      lines << "**Success Criteria**: #{plan['success_criteria'].join('; ')}"
      lines << "**Estimated Duration**: #{plan['estimated_duration']}"
      lines << ""
      lines << "Ready to execute. I'll work through each phase step by step."
      
      lines.join("\n")
    end
  end
end
