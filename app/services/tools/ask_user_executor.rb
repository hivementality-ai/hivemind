# frozen_string_literal: true

module Tools
  class AskUserExecutor < BaseExecutor
    REDIS_KEY_PREFIX = "ask_user_pending"
    DEFAULT_TIMEOUT = 300 # 5 minutes

    def call
      questions = parse_questions

      if questions.empty?
        return ServiceResponse.failure(error: "questions cannot be blank")
      end

      session_id = config[:session]&.id
      unless session_id
        return ServiceResponse.failure(error: "Session required for ask_user tool")
      end

      # Store the pending questions in Redis
      redis_key = "#{REDIS_KEY_PREFIX}:#{session_id}"
      pending_data = {
        questions: questions,
        asked_at: Time.current.iso8601,
        timeout_at: (Time.current + DEFAULT_TIMEOUT).iso8601,
        session_id: session_id,
        agent_id: agent&.id
      }.to_json

      Rails.cache.write(redis_key, pending_data, expires_in: DEFAULT_TIMEOUT + 60)

      # Broadcast the questions to the session channel
      session = config[:session]
      channel = "session_#{session_id}"
      ActionCable.server.broadcast(channel, {
        type: "agent_question",
        questions: questions,
        timestamp: Time.current.iso8601
      })

      # Also broadcast to team chat channel if this is a team chat session
      if session.respond_to?(:team_chat_session) && session.team_chat_session.present?
        ActionCable.server.broadcast("team_chat_#{session.team_chat_session.id}", {
          type: "agent_question",
          agent_id: agent&.id,
          agent_name: agent&.name,
          questions: questions,
          timestamp: Time.current.iso8601
        })
      end

      # Wait for user response with timeout
      timeout_at = Time.current + DEFAULT_TIMEOUT
      response = nil

      loop do
        cached_data = Rails.cache.read(redis_key)
        if cached_data
          parsed_data = JSON.parse(cached_data)
          if parsed_data["answer"]
            response = parsed_data["answer"]
            Rails.cache.delete(redis_key)
            break
          end
        else
          # Key was deleted (answered or expired)
          break
        end

        if Time.current > timeout_at
          Rails.cache.delete(redis_key)
          return ServiceResponse.failure(error: "Question timed out - no response received within #{DEFAULT_TIMEOUT} seconds")
        end

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
      redis_key = "#{REDIS_KEY_PREFIX}:#{session_id}" if session_id
      Rails.cache.delete(redis_key) if redis_key
      ServiceResponse.failure(error: "Ask user failed: #{e.message}")
    end

    private

    # Normalise input: accepts either the new `questions` array format or a
    # legacy plain `question` string so old cached tool definitions don't break.
    def parse_questions
      if input["questions"].is_a?(Array) && input["questions"].any?
        input["questions"].filter_map do |q|
          question_text = q["question"].to_s.strip
          next if question_text.blank?

          {
            "question" => question_text,
            "header"   => q["header"].to_s.strip.presence,
            "options"  => Array(q["options"]).map { |o|
              { "label" => o["label"].to_s, "description" => o["description"].to_s.presence }
            },
            "multiSelect" => q["multiSelect"] == true
          }
        end
      elsif input["question"].present?
        # Legacy single-question fallback — no options, free-text only
        [ {
          "question"    => input["question"].to_s.strip,
          "header"      => nil,
          "options"     => [],
          "multiSelect" => false
        } ]
      else
        []
      end
    end
  end
end
