# frozen_string_literal: true

# Clears chat turns whose worker died mid-reply (deploy, crash, OOM). A live
# turn holds a heartbeat-renewed lock, so a processing flag with no lock means
# the worker is gone and the UI would otherwise spin forever.
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
    session_id = key.delete_prefix(ChatStreamJob::PROCESSING_KEY_PREFIX)
    return false if Redis.current.exists?("#{ChatStreamJob::LOCK_KEY_PREFIX}#{session_id}")

    return false if Redis.current.del(key).zero?

    session = Session.find_by(id: session_id)
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
