# frozen_string_literal: true

class SessionArchivalJob < ApplicationJob
  queue_as :low

  # Archive sessions inactive for more than 7 days.
  # Moves transcript to transcript_archives and marks session as archived.
  INACTIVE_THRESHOLD = 7.days

  def perform
    sessions = Session.where(status: :active)
                      .where("last_activity_at < ?", INACTIVE_THRESHOLD.ago)

    archived_count = 0

    sessions.find_each do |session|
      next if session.transcript.blank?

      session.transcript_archives.create!(
        content: session.transcript,
        archived_at: Time.current
      )

      session.update!(
        status: :archived,
        transcript: []
      )

      archived_count += 1
    rescue StandardError => e
      Rails.logger.error("[SessionArchivalJob] Failed to archive session #{session.id}: #{e.message}")
    end

    Rails.logger.info("[SessionArchivalJob] Archived #{archived_count} sessions")
  end
end
