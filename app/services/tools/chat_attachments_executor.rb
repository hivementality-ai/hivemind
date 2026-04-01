# frozen_string_literal: true

module Tools
  class ChatAttachmentsExecutor < BaseExecutor
    WORKSPACE_ROOT = "/workspace"

    def call
      @session = config[:session]
      return ServiceResponse.failure(error: "No session context available") unless @session

      action = input["action"].to_s.strip.presence || "list"

      case action
      when "list"
        list_attachments
      when "download"
        download_attachment
      else
        ServiceResponse.failure(error: "Unknown action: #{action}. Use 'list' or 'download'.")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Chat attachments failed: #{e.message}")
    end

    private

    def list_attachments
      entries = collect_all_attachments

      if entries.empty?
        return ServiceResponse.success(data: { output: "No attachments in this chat session.", exit_code: 0 })
      end

      lines = entries.map do |e|
        "  id=#{e[:id]}  #{e[:filename]}  (#{e[:content_type]}, #{format_size(e[:byte_size])}, #{e[:type_label]})  uploaded #{e[:created_at]}"
      end

      output = "#{entries.size} attachment(s) in this session:\n#{lines.join("\n")}\n\nUse action='download' with attachment_id to save a file to the workspace."
      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def download_attachment
      attachment_id = input["attachment_id"]
      return ServiceResponse.failure(error: "No attachment_id provided") if attachment_id.blank?

      # Try 1:1 chat attachments first
      attachment = @session.chat_attachments.find_by(id: attachment_id)
      if attachment
        return download_chat_attachment(attachment)
      end

      # Try team chat message attachments (ActiveStorage blobs)
      if @session.team_chat_session.present?
        blob = find_team_chat_blob(attachment_id.to_i)
        return download_blob(blob) if blob
      end

      ServiceResponse.failure(error: "Attachment #{attachment_id} not found in this session")
    end

    # Collect attachments from both 1:1 and team chat paths into a unified list
    def collect_all_attachments
      entries = []

      # 1:1 chat attachments
      @session.chat_attachments.order(created_at: :desc).each do |a|
        entries << {
          id: a.id,
          filename: a.filename.to_s,
          content_type: a.content_type,
          byte_size: a.byte_size || 0,
          type_label: a.image? ? "image" : "document",
          created_at: a.created_at.strftime("%Y-%m-%d %H:%M")
        }
      end

      # Team chat message attachments (images + documents on TeamChatMessage)
      if @session.team_chat_session.present?
        @session.team_chat_session.team_chat_messages.each do |msg|
          msg.images.each do |img|
            entries << blob_entry(img, "image")
          end
          msg.documents.each do |doc|
            entries << blob_entry(doc, "document")
          end
        end
      end

      entries
    end

    def blob_entry(active_storage_attachment, type_label)
      blob = active_storage_attachment.blob
      {
        id: blob.id,
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size || 0,
        type_label: type_label,
        created_at: blob.created_at.strftime("%Y-%m-%d %H:%M")
      }
    end

    def find_team_chat_blob(blob_id)
      @session.team_chat_session.team_chat_messages.each do |msg|
        msg.images.each { |img| return img.blob if img.blob.id == blob_id }
        msg.documents.each { |doc| return doc.blob if doc.blob.id == blob_id }
      end
      nil
    end

    def download_chat_attachment(attachment)
      return ServiceResponse.failure(error: "File not attached to record") unless attachment.file.attached?

      dest_path = write_to_workspace(attachment.filename.to_s, attachment.file.download)
      size = format_size(attachment.byte_size || 0)

      output = "Downloaded #{attachment.filename} to #{dest_path} (#{size})"
      output += "\nUse file_read to read this file." if attachment.document?
      output += "\nThis is an image file — use the image tool to analyze it." if attachment.image?

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def download_blob(blob)
      dest_path = write_to_workspace(blob.filename.to_s, blob.download)
      size = format_size(blob.byte_size || 0)
      is_image = blob.content_type&.start_with?("image/")

      output = "Downloaded #{blob.filename} to #{dest_path} (#{size})"
      output += "\nUse file_read to read this file." unless is_image
      output += "\nThis is an image file — use the image tool to analyze it." if is_image

      ServiceResponse.success(data: { output: output, exit_code: 0 })
    end

    def write_to_workspace(filename, data)
      dest_dir = File.join(WORKSPACE_ROOT, "downloads")
      FileUtils.mkdir_p(dest_dir)

      safe_name = filename.gsub(/[^a-zA-Z0-9._-]/, "_")
      dest_path = File.join(dest_dir, safe_name)

      if File.exist?(dest_path)
        base = File.basename(safe_name, File.extname(safe_name))
        ext = File.extname(safe_name)
        dest_path = File.join(dest_dir, "#{base}_#{Time.current.strftime('%H%M%S')}#{ext}")
      end

      File.binwrite(dest_path, data)
      dest_path
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
