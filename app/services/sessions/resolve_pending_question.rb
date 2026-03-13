# frozen_string_literal: true

module Sessions
  class ResolvePendingQuestion
    def self.call(session:, user_message:)
      new(session:, user_message:).call
    end

    def initialize(session:, user_message:)
      @session = session
      @user_message = user_message
    end

    def call
      redis_key = "ask_user_pending:#{@session.id}"
      cached_data = Rails.cache.read(redis_key)

      return ServiceResponse.failure(error: "no_pending_question") unless cached_data

      parsed_data = JSON.parse(cached_data)

      # Check if question hasn't timed out
      timeout_at = Time.parse(parsed_data["timeout_at"])
      if Time.current > timeout_at
        Rails.cache.delete(redis_key)
        return ServiceResponse.failure(error: "question_timed_out")
      end

      # Store the user's answer in the cached data
      parsed_data["answer"] = @user_message
      parsed_data["answered_at"] = Time.current.iso8601
      Rails.cache.write(redis_key, parsed_data.to_json, expires_in: 60)

      # Broadcast the user's response to show it in chat
      ActionCable.server.broadcast("session_#{@session.id}", {
        type: "user_message",
        content: @user_message
      })

      # Add to transcript
      @session.transcript << {
        "role" => "user",
        "content" => @user_message,
        "timestamp" => Time.current.iso8601,
        "is_question_response" => true
      }
      @session.save!

      ServiceResponse.success
    rescue JSON::ParserError
      Rails.cache.delete("ask_user_pending:#{@session.id}")
      ServiceResponse.failure(error: "invalid_cached_data")
    end
  end
end