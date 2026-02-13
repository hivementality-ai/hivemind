# frozen_string_literal: true

class Session < ApplicationRecord
  belongs_to :agent
  belongs_to :team_chat_session, optional: true

  has_many :transcript_archives, dependent: :destroy
  has_many :usage_records, dependent: :destroy
  has_many :chat_attachments, dependent: :destroy

  enum :status, { active: 0, completed: 1, archived: 2, expired: 3 }, default: :active

  validates :session_key, presence: true, uniqueness: true

  scope :active_sessions, -> { where(status: :active) }
  scope :recent, -> { where("last_activity_at > ?", 24.hours.ago) }

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
