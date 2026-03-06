# frozen_string_literal: true

module Tools
  class AskUserExecutor < BaseExecutor
    REDIS_KEY_PREFIX = "ask_user_pending"
    DEFAULT_TIMEOUT = 300 # 5 minutes

    def call
      question = input["question"].to_s.strip

      if question.blank?
        return ServiceResponse.failure(error: "Question cannot be blank")
      end

      session_id = config[:session]&.id
      unless session_id
        return ServiceResponse.failure(error: "Session required for ask_user tool")
      end

      # Store the pending question in Redis
      redis_key = "#{REDIS_KEY_PREFIX}:#{session_id}"
      pending_data = {
        question: question,
        asked_at: Time.current.iso8601,
        timeout_at: (Time.current + DEFAULT_TIMEOUT).iso8601,
        session_id: session_id,
        agent_id: agent&.id
      }.to_json

      Rails.cache.write(redis_key, pending_data, expires_in: DEFAULT_TIMEOUT + 60)

      # Broadcast the question to the chat
      session = config[:session]
      channel = "session_#{session_id}"
      ActionCable.server.broadcast(channel, {
        type: "agent_question",
        question: question,
        timestamp: Time.current.iso8601
      })

      # Also broadcast to team chat channel if this is a team chat session
      if session.respond_to?(:team_chat_session) && session.team_chat_session.present?
        ActionCable.server.broadcast("team_chat_#{session.team_chat_session.id}", {
          type: "agent_question",
          agent_id: agent&.id,
          agent_name: agent&.name,
          question: question,
          timestamp: Time.current.iso8601
        })
      end

      # Wait for user response with timeout
      timeout_at = Time.current + DEFAULT_TIMEOUT
      response = nil

      loop do
        # Check if question was answered
        cached_data = Rails.cache.read(redis_key)
        if cached_data
          parsed_data = JSON.parse(cached_data)
          if parsed_data["answer"]
            response = parsed_data["answer"]
            # Clean up the pending question
            Rails.cache.delete(redis_key)
            break
          end
        else
          # Question was deleted (likely answered)
          break
        end

        # Check timeout
        if Time.current > timeout_at
          Rails.cache.delete(redis_key)
          return ServiceResponse.failure(error: "Question timed out - no response received within #{DEFAULT_TIMEOUT} seconds")
        end

        # Wait a bit before checking again
        sleep(0.5)
      end

      if response.present?
        ServiceResponse.success(data: {
          output: "User responded: #{response}",
          user_response: response,
          exit_code: 0
        })
      else
        ServiceResponse.failure(error: "No response received from user")
      end
    rescue StandardError => e
      # Clean up on any error
      redis_key = "#{REDIS_KEY_PREFIX}:#{session_id}" if session_id
      Rails.cache.delete(redis_key) if redis_key
      ServiceResponse.failure(error: "Ask user failed: #{e.message}")
    end
  end
end
