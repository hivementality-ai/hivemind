# frozen_string_literal: true

module Sessions
  class AttachmentProcessor
    def self.call(...)
      new(...).call
    end

    def initialize(attachment_ids:, user_message:)
      @attachment_ids = attachment_ids
      @user_message = user_message
    end

    def call
      attachments = @attachment_ids.present? ? ChatAttachment.where(id: @attachment_ids) : []
      images = attachments.select(&:image?)
      documents = attachments.select(&:document?)

      effective_message = @user_message
      saved_paths = []

      if documents.any?
        saved_paths = save_docs_to_workspace(documents)
        if saved_paths.any?
          file_list = saved_paths.map do |f|
            line = "  - #{f[:path]} (#{f[:filename]}, #{f[:size]})"
            line += " — #{f[:note]}" if f[:note]
            line
          end.join("\n")
          effective_message = "#{effective_message}\n\n[Attached Files — saved to workspace]\n#{file_list}\n\nUse the file_read tool to read these files."
        end
      end

      ServiceResponse.success(data: {
        images: images,
        documents: documents,
        effective_message: effective_message,
        saved_paths: saved_paths
      })
    rescue StandardError => e
      Rails.logger.error("[Sessions::AttachmentProcessor] Error: #{e.message}")
      ServiceResponse.failure(error: e.message)
    end

    private

    def save_docs_to_workspace(doc_attachments)
      upload_dir = "/workspace/uploads/#{Date.current.iso8601}"
      FileUtils.mkdir_p(upload_dir)

      doc_attachments.filter_map do |doc|
        next unless doc.file.attached?

        safe_name = doc.filename.to_s.gsub(/[^a-zA-Z0-9._-]/, "_")
        timestamped = "#{Time.current.strftime('%H%M%S')}_#{safe_name}"
        path = File.join(upload_dir, timestamped)
        data = doc.file.download

        File.binwrite(path, data)

        size = if doc.byte_size < 1024
                 "#{doc.byte_size}B"
        elsif doc.byte_size < 1_048_576
                 "#{(doc.byte_size / 1024.0).round(1)}KB"
        else
                 "#{(doc.byte_size / 1_048_576.0).round(1)}MB"
        end

        result = { path: path, filename: doc.filename.to_s, size: size }

        if doc.content_type == "application/pdf"
          result[:note] = "PDF — use the pdf_read tool (not file_read) to extract text, metadata, or tables"
        elsif !doc.content_type.to_s.start_with?("text/") && !%w[application/json application/xml].include?(doc.content_type)
          result[:note] = "Binary file — may not be directly readable with file_read"
        end

        result
      rescue StandardError => e
        Rails.logger.warn("Failed to save doc to workspace: #{e.message}")
        nil
      end
    end
  end
end
