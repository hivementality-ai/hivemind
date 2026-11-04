# frozen_string_literal: true

# Clears chat turns whose worker died mid-reply (deploy, crash, OOM). Such a
# turn leaves its processing flag and turn lock behind, so the UI spins and
# later messages queue behind a lock nobody holds.
class StuckTurnSweepJob < ApplicationJob
  queue_as :system

  INTERRUPTED_MESSAGE = "This reply was interrupted. Send your message again to retry."

  # @return [Integer] number of sessions cleared
  def perform
    cleared = 0
    Redis.current.scan_each(match: "#{ChatStreamJob::PROCESSING_KEY_PREFIX}*") do |key|
      cleared += 1 if sweep(key)
    end
    Rails.logger.info("[StuckTurnSweepJob] Cleared #{cleared} interrupted turns") if cleared.positive?
    cleared
  end

  private

  def sweep(key)
    remaining = Redis.current.ttl(key)
    return false if remaining.negative?
    return false if ChatStreamJob::PROCESSING_TTL - remaining < ChatStreamJob::STALE_AFTER

    session_id = key.delete_prefix(ChatStreamJob::PROCESSING_KEY_PREFIX)
    session = Session.find_by(id: session_id)
    return false if session&.last_activity_at && session.last_activity_at > ChatStreamJob::STALE_AFTER.seconds.ago

    Redis.current.del(key, "#{ChatStreamJob::LOCK_KEY_PREFIX}#{session_id}")
    notify(session) if session
    true
  rescue StandardError => e
    Rails.logger.warn("[StuckTurnSweepJob] Failed to sweep #{key}: #{e.message}")
    false
  end

  def notify(session)
    session.append_transcript({ "role" => "assistant", "content" => INTERRUPTED_MESSAGE })
    channel = "session_#{session.id}"
    ActionCable.server.broadcast(channel, { type: "error", content: INTERRUPTED_MESSAGE })
    ActionCable.server.broadcast(channel, { type: "processing", active: false })
  end
end
