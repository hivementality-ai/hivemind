# frozen_string_literal: true

class TaskAttachment < ApplicationRecord
  belongs_to :task

  validates :title,        presence: true
  validates :url,          presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid http/https URL" }
  validates :content_type, length: { maximum: 255 }
  validates :uploaded_by,  length: { maximum: 255 }

  scope :recent, -> { order(created_at: :desc) }

  # Best-effort content type from URL extension when not explicitly set.
  def resolved_content_type
    return content_type if content_type.present?

    ext = File.extname(URI.parse(url).path).downcase.delete(".")
    EXTENSION_TYPES.fetch(ext, "application/octet-stream")
  rescue URI::InvalidURIError
    "application/octet-stream"
  end

  # Returns a display label for the attachment type (for UI icons / badges).
  def kind
    ct = resolved_content_type
    if ct.start_with?("image/")
      "image"
    elsif ct == "application/pdf"
      "pdf"
    elsif ct.include?("spreadsheet") || ct.include?("excel") || ct.end_with?("csv")
      "spreadsheet"
    elsif ct.include?("document") || ct.include?("word") || ct == "text/plain"
      "document"
    else
      "link"
    end
  end

  private

  EXTENSION_TYPES = {
    "jpg"  => "image/jpeg",
    "jpeg" => "image/jpeg",
    "png"  => "image/png",
    "gif"  => "image/gif",
    "webp" => "image/webp",
    "pdf"  => "application/pdf",
    "csv"  => "text/csv",
    "txt"  => "text/plain",
    "md"   => "text/markdown",
    "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
  }.freeze
end
