# frozen_string_literal: true

module Tools
  class SessionsHistoryExecutor < BaseExecutor
    def call
      session_key = input["session_key"].to_s.strip
      limit = (input["limit"] || 20).to_i.clamp(1, 50)

      return ServiceResponse.failure(error: "No session_key provided") if session_key.empty?

      session = Session.find_by(session_key: session_key)
      return ServiceResponse.failure(error: "Session not found: #{session_key}") unless session

      transcript = session.transcript || []
      messages = transcript.last(limit)

      if messages.any?
        output = messages.map do |msg|
          role = msg["role"] || "unknown"
          content = (msg["content"] || "").truncate(500)
          "[#{role}] #{content}"
        end.join("\n\n")

        ServiceResponse.success(data: {
          output: "Session: #{session.title || session_key} (#{transcript.size} total messages)\nLast #{messages.size}:\n\n#{output}",
          exit_code: 0
        })
      else
        ServiceResponse.success(data: { output: "Session has no messages.", exit_code: 0 })
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Sessions history failed: #{e.message}")
    end
  end
end
