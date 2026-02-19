# frozen_string_literal: true

require "stringio"

module Tools
  class FileSendExecutor < BaseExecutor
    WORKSPACE_ROOT = WorkspaceIO::WORKSPACE_ROOT

    def call
      path = input["path"].to_s.strip
      filename = input["filename"].to_s.strip.presence || File.basename(path)

      return ServiceResponse.failure(error: "No path provided") if path.empty?

      full_path = path.start_with?("/") ? path : File.join(WORKSPACE_ROOT, path)

      unless full_path.start_with?(WORKSPACE_ROOT)
        return ServiceResponse.failure(error: "Access denied: path must be within /workspace")
      end

      unless WorkspaceIO.file_exists?(full_path)
        return ServiceResponse.failure(error: "File not found: #{path}")
      end

      # Read file content via workspace container
      content = WorkspaceIO.read_file(full_path)
      byte_size = content.bytesize

      # Detect MIME type
      extension = File.extname(filename)
      content_type = Marcel::MimeType.for(name: filename, extension: extension) || "application/octet-stream"

      # Create ChatAttachment
      session = resolve_session
      return ServiceResponse.failure(error: "No session context available") unless session

      attachment = session.chat_attachments.create!(
        content_type: content_type,
        filename: filename,
        byte_size: byte_size
      )

      # Attach file via ActiveStorage
      attachment.file.attach(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type
      )

      # Broadcast to session channel
      broadcast_attachment(session, attachment)

      ServiceResponse.success(
        data: {
          output: "Sent #{filename} (#{format_size(byte_size)}, #{content_type}) to chat",
          exit_code: 0,
          attachment_id: attachment.id
        }
      )
    rescue StandardError => e
      ServiceResponse.failure(error: "Failed to send file: #{e.message}")
    end

    private

    def resolve_session
      # Try to get session from config (passed by tool executor dispatcher)
      return config[:session] if config[:session]

      # Try to get from agent's most recent session
      return agent.sessions.order(updated_at: :desc).first if agent

      nil
    end

    def broadcast_attachment(session, attachment)
      blob_url = Rails.application.routes.url_helpers.rails_blob_path(
        attachment.file,
        only_path: true
      )

      attachment_data = {
        id: attachment.id,
        filename: attachment.filename,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        url: blob_url,
        is_image: attachment.image?
      }

      # Determine if this is team chat or regular agent chat
      if session.team_chat_session.present?
        # Team chat context
        channel = "team_chat_#{session.team_chat_session_id}"
        broadcast_data = {
          type: "file_attachment",
          agent_id: agent.id,
          agent_name: agent.name,
          attachment: attachment_data
        }
      else
        # Regular agent chat
        channel = "session_#{session.id}"
        broadcast_data = {
          type: "file_attachment",
          attachment: attachment_data
        }
      end

      ActionCable.server.broadcast(channel, broadcast_data)
    end

    def format_size(bytes)
      if bytes < 1024
        "#{bytes}B"
      elsif bytes < 1_048_576
        "#{(bytes / 1024.0).round(1)}KB"
      else
        "#{(bytes / 1_048_576.0).round(1)}MB"
      end
    end
  end
end
