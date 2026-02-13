# frozen_string_literal: true

module Tools
  class SessionsListExecutor < BaseExecutor
    def call
      limit = (input["limit"] || 20).to_i.clamp(1, 50)
      status_filter = input["status"].to_s.strip.presence

      sessions = Session.includes(:agent).order(updated_at: :desc)
      sessions = sessions.where(status: status_filter) if status_filter
      sessions = sessions.limit(limit)

      if sessions.any?
        output = sessions.map do |s|
          agent_name = s.agent&.name || "—"
          msgs = s.transcript&.size || 0
          "• [#{s.session_key}] #{s.title || "Untitled"} — #{agent_name} (#{s.status}, #{msgs} msgs, #{s.updated_at.strftime("%b %d %H:%M")})"
        end.join("\n")
        ServiceResponse.success(data: { output: "Sessions (#{sessions.size}):\n#{output}", exit_code: 0 })
      else
        ServiceResponse.success(data: { output: "No sessions found.", exit_code: 0 })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Sessions list failed: #{e.message}")
    end
  end
end
