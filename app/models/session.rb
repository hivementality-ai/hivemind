# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :agent
  belongs_to :team_chat_session, optional: true
  belongs_to :origin_channel, class_name: "Channel", optional: true, foreign_key: :origin_channel_id

  has_many :transcript_archives, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :chat_attachments, dependent: :destroy
  has_many :tool_executions, dependent: :destroy
  has_many :coding_agent_tasks, dependent: :destroy
  has_many :research_sessions, dependent: :destroy
  has_many :heartbeat_runs, dependent: :destroy
  has_many :sub_agent_tasks_as_parent, class_name: "SubAgentTask", foreign_key: :parent_session_id, dependent: :nullify
  has_many :sub_agent_tasks_as_child, class_name: "SubAgentTask", foreign_key: :child_session_id, dependent: :nullify

  enum :status, { active: 0, completed: 1, archived: 2, expired: 3 }, default: :active

  validates :session_key, presence: true, uniqueness: true

  scope :active_sessions, -> { where(status: :active) }
  scope :recent, -> { where("last_activity_at > ?", 24.hours.ago) }
  scope :from_whatsapp, -> { where(origin_channel_type: "whatsapp") }

  def whatsapp_origin?
    origin_channel_type == "whatsapp"
  end

  def origin_delivery_info
    return nil unless origin_channel_type.present? && origin_sender.present?
    { channel_type: origin_channel_type, channel_id: origin_channel_id, sender: origin_sender }
  end

  before_save :sanitize_transcript_encoding
  after_initialize :set_defaults

  def append_transcript(entry)
    self.transcript ||= []
    sanitized = entry.transform_values { |v| v.is_a?(String) ? sanitize_utf8(v) : v }
    self.transcript << sanitized.merge(timestamp: Time.current.iso8601)
    self.last_activity_at = Time.current
    save!
  end

  def transcript_size
    (transcript || []).size
  end

  def transcript_summary
    {
      total_entries: transcript_size,
      first_entry_at: transcript&.first&.dig("timestamp"),
      last_entry_at: transcript&.last&.dig("timestamp"),
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens
    }
  end

  # Alias for compatibility
  def key
    session_key
  end

  private

  def sanitize_utf8(str)
    str.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
       .gsub(/\xC2\xA0/, " ") # non-breaking space
       .scrub(" ")
  end

  def sanitize_transcript_encoding
    return unless transcript.is_a?(Array)

    self.transcript = transcript.map do |entry|
      next entry unless entry.is_a?(Hash)

      entry.transform_values { |v| v.is_a?(String) ? sanitize_utf8(v) : v }
    end
  end

  def set_defaults
    self.transcript ||= []
    self.metadata ||= {}
    self.input_tokens ||= 0
    self.output_tokens ||= 0
    self.total_tokens ||= 0
  end
end
