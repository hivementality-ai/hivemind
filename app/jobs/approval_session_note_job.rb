# frozen_string_literal: true

# Adds an approval outcome to a chat session's transcript without racing a running
# turn. A turn saves its own copy of the transcript when it ends, which would erase
# a note written meanwhile, so the note is written only while holding the same
# per-session lock ChatStreamJob takes. While a turn runs, the job tries again later.
class ApprovalSessionNoteJob < ApplicationJob
  queue_as :default

  RETRY_DELAY = 5.seconds
  GIVE_UP_AFTER = 10.minutes

  # @param session_id [Integer]
  # @param content [String] note text
  # @param deadline [Integer, nil] epoch seconds after which the note is dropped; set on first run
  def perform(session_id, content, deadline = nil)
    deadline ||= GIVE_UP_AFTER.from_now.to_i
    token = SecureRandom.hex(8)
    lock_key = "#{ChatStreamJob::LOCK_KEY_PREFIX}#{session_id}"

    if Redis.current.set(lock_key, token, nx: true, ex: ChatStreamJob::LOCK_TTL)
      begin
        write_note(session_id, content)
      ensure
        ChatStreamJob.release_lock(lock_key, token)
      end
    elsif Time.current.to_i < deadline
      self.class.set(wait: RETRY_DELAY).perform_later(session_id, content, deadline)
    else
      Rails.logger.warn("[ApprovalSessionNoteJob] gave up on session #{session_id}: a turn stayed running")
    end
  end

  private

  def write_note(session_id, content)
    session = Session.find_by(id: session_id)
    return unless session

    session.append_transcript({ "role" => "assistant", "content" => content })
    ActionCable.server.broadcast("session_#{session.id}", { type: "notice", content: content })
  end
end
