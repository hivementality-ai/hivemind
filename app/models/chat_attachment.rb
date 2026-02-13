# frozen_string_literal: true

class ChatAttachment < ApplicationRecord
  belongs_to :session

  has_one_attached :file

  validates :content_type, presence: true

  SUPPORTED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  SUPPORTED_DOCUMENT_TYPES = %w[
    text/plain
    text/markdown
    text/csv
    text/html
    text/xml
    application/json
    application/xml
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
    application/vnd.ms-excel
    application/msword
  ].freeze

  SUPPORTED_TYPES = (SUPPORTED_IMAGE_TYPES + SUPPORTED_DOCUMENT_TYPES).freeze

  def image?
    content_type.in?(SUPPORTED_IMAGE_TYPES)
  end

  def document?
    !image?
  end

  def text_extractable?
    content_type.in?(%w[text/plain text/markdown text/csv text/html text/xml application/json application/xml])
  end

  # Extract text content from document for LLM context
  def extract_text
    return nil unless file.attached?

    if text_extractable?
      file.download.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    elsif content_type == "application/pdf"
      extract_pdf_text
    else
      # For binary formats (docx, xlsx), provide filename as context
      "[Uploaded file: #{filename} (#{content_type}, #{byte_size} bytes)]"
    end
  rescue StandardError => e
    "[Could not read file: #{filename} — #{e.message}]"
  end

  # Base64 encode for LLM vision APIs
  def to_base64
    return nil unless file.attached?

    Base64.strict_encode64(file.download)
  end

  # Media type for Anthropic API (e.g., "image/jpeg")
  def media_type
    content_type
  end

  private

  def extract_pdf_text
    # Simple PDF text extraction — looks for text streams
    raw = file.download
    text = raw.scan(/\((.*?)\)/).flatten.join(" ")
    text = raw.scan(/BT\s*(.*?)\s*ET/m).flatten.join(" ") if text.blank?
    text.presence || "[PDF file: #{filename} (#{byte_size} bytes) — text extraction limited, content may be scanned/image-based]"
  rescue StandardError
    "[PDF file: #{filename} (#{byte_size} bytes)]"
  end
end
