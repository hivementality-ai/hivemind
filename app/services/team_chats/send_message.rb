# frozen_string_literal: true

module TeamChats
  class SendMessage
    def self.call(session:, user:, message:, images: nil, files: nil)
      new(session:, user:, message:, images:, files:).call
    end

    def initialize(session:, user:, message:, images: nil, files: nil)
      @session = session
      @user = user
      @message = message
      @images = images
      @files = files
    end

    def call
      # Check if any agent has a pending ask_user question
      if handle_pending_question
        return ServiceResponse.success(data: { message: nil, question_answered: true })
      end

      team = @session.team
      mentions = TeamChatMessage.extract_mentions(@message.to_s, team)
      target_agent = mentions[:agents].first if mentions[:agents].size == 1 && !mentions[:broadcast]

      msg = create_message(target_agent)
      return ServiceResponse.failure(error: msg.errors.full_messages) unless msg.persisted?

      attach_files(msg)
      @session.touch

      broadcast_message(msg, target_agent)
      trigger_agent_responses(msg)

      ServiceResponse.success(data: { message: msg })
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to send message: #{e.message}")
    end

    private

    def handle_pending_question
      # Check each agent's session for a pending ask_user question
      @session.agent_sessions.each do |agent_session|
        redis_key = "ask_user_pending:#{agent_session.id}"
        cached_data = Rails.cache.read(redis_key)
        next unless cached_data

        begin
          parsed_data = JSON.parse(cached_data)

          timeout_at = Time.parse(parsed_data["timeout_at"])
          if Time.current > timeout_at
            Rails.cache.delete(redis_key)
            next
          end

          # Store the user's answer so the polling executor picks it up
          parsed_data["answer"] = @message
          parsed_data["answered_at"] = Time.current.iso8601
          Rails.cache.write(redis_key, parsed_data.to_json, expires_in: 60)

          # Save user message to team chat for visibility
          @session.team_chat_messages.create!(
            sender_type: "user",
            sender_id: @user.id,
            content: @message.to_s.presence || "[response]"
          )

          # Broadcast so the UI shows the response
          ActionCable.server.broadcast("team_chat_#{@session.id}", {
            type: "user_message",
            content: @message.to_s
          })

          return true
        rescue JSON::ParserError
          Rails.cache.delete(redis_key)
          next
        end
      end

      false
    end

    def create_message(target_agent)
      @session.team_chat_messages.create(
        sender_type: "user",
        sender_id: @user.id,
        target_agent_id: target_agent&.id,
        content: @message.to_s.presence || "[image]"
      )
    end

    def attach_files(msg)
      [ @images, @files ].compact.each do |file_list|
        Array(file_list).each do |upload|
          next unless upload.respond_to?(:content_type)

          if upload.content_type.start_with?("image/")
            msg.images.attach(upload)
          else
            msg.documents.attach(upload)
          end
        end
      end
    end

    def broadcast_message(msg, target_agent)
      image_urls = msg.images.map do |img|
        {
          url: Rails.application.routes.url_helpers.rails_blob_path(img, only_path: true),
          filename: img.filename.to_s
        }
      end

      file_info = if msg.documents.attached?
                    msg.documents.map { |d| { filename: d.filename.to_s, byte_size: d.byte_size } }
      else
                    []
      end

      ActionCable.server.broadcast("team_chat_#{@session.id}", {
        type: "user_message",
        content: @message.to_s,
        target_agent_id: target_agent&.id,
        target_agent_name: target_agent&.name,
        message_id: msg.id,
        images: image_urls.presence,
        files: file_info.presence
      })
    end

    def trigger_agent_responses(msg)
      TeamChatJob.perform_later(@session.id, msg.id)
    end
  end
end
