# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :agent
  belongs_to :team_chat_session, optional: true
  belongs_to :origin_channel, class_name: "Channel", optional: true, foreign_key: :origin_channel_id

  has_many :transcript_archives, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :chat_attachments, dependent: :destroy

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

  after_initialize :set_defaults

  def append_transcript(entry)
    self.transcript ||= []
    self.transcript << entry.merge(timestamp: Time.current.iso8601)
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

  def set_defaults
    self.transcript ||= []
    self.metadata ||= {}
    self.input_tokens ||= 0
    self.output_tokens ||= 0
    self.total_tokens ||= 0
  end
end
