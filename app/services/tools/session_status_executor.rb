# frozen_string_literal: true

module Tools
  class SessionStatusExecutor < BaseExecutor
    def call
      session_key = input["session_key"].to_s.strip

      # If no key given, show agent's most recent session
      session = if session_key.present?
                  Session.find_by(session_key: session_key)
      elsif agent
                  Session.where(agent: agent).order(updated_at: :desc).first
      end

      return ServiceResponse.failure(error: "No session found") unless session

      usage = UsageRecord.where(session: session)
      total_tokens = usage.sum("input_tokens + output_tokens")
      total_cost = usage.sum(:cost_cents) / 100.0
      request_count = usage.count
      models_used = usage.distinct.pluck(:llm_model)

      output = []
      output << "Session: #{session.title || session.session_key}"
      output << "Agent: #{session.agent&.name || '—'}"
      output << "Status: #{session.status}"
      output << "Messages: #{session.transcript&.size || 0}"
      output << "API Requests: #{request_count}"
      output << "Total Tokens: #{total_tokens}"
      output << "Total Cost: $#{sprintf("%.4f", total_cost)}"
      output << "Models: #{models_used.join(", ")}" if models_used.any?
      output << "Created: #{session.created_at.strftime("%Y-%m-%d %H:%M")}"
      output << "Last Active: #{session.updated_at.strftime("%Y-%m-%d %H:%M")}"

      ServiceResponse.success(data: { output: output.join("\n"), exit_code: 0 })
    rescue StandardError => e
      ServiceResponse.failure(error: "Session status failed: #{e.message}")
    end
  end
end
