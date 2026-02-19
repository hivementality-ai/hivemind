# frozen_string_literal: true

module Tools
  class PlanModeExecutor < BaseExecutor
    def call
      action = input["action"]&.downcase
      session = config[:session]

      case action
      when "enter"
        enter_planning_mode(session)
      when "exit"
        exit_planning_mode(session)
      else
        ServiceResponse.failure(error: "Invalid action. Use 'enter' or 'exit'")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Planning mode operation failed: #{e.message}")
    end

    private

    def enter_planning_mode(session)
      # Set planning mode flag in session metadata
      session.metadata ||= {}
      session.metadata["planning_mode"] = true
      session.metadata["planning_started_at"] = Time.current.iso8601
      session.save!

      # Broadcast planning state to UI
      ActionCable.server.broadcast(
        "session_#{session.id}",
        {
          type: "planning_mode",
          planning: true,
          message: "🧠 Planning mode activated..."
        }
      )

      output = "Planning mode activated. Tool calls will be shown in planning context."
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def exit_planning_mode(session)
      summary = input["summary"]&.strip

      # Clear planning mode flag and add summary if provided
      session.metadata ||= {}
      session.metadata["planning_mode"] = false
      session.metadata["planning_ended_at"] = Time.current.iso8601

      if summary.present?
        session.metadata["last_planning_summary"] = summary
      end

      session.save!

      # Broadcast planning state to UI
      broadcast_data = {
        type: "planning_mode",
        planning: false,
        message: "📋 Switched to implementation mode"
      }

      if summary.present?
        broadcast_data[:summary] = summary
      end

      ActionCable.server.broadcast("session_#{session.id}", broadcast_data)

      output_parts = [ "Planning mode deactivated." ]
      if summary.present?
        output_parts << "Plan summary recorded."
      end

      ServiceResponse.success(data: { output: output_parts.join(" "), exit_code: 0 })
    end
  end
end
