# frozen_string_literal: true

# One recording a person dropped into a chat, from upload through transcript
# and notes. The audio itself is purged once transcription succeeds unless the
# person asked to keep it.
class AudioNote < ApplicationRecord
  belongs_to :session
  belongs_to :agent
  belongs_to :knowledge_document, optional: true

  has_one_attached :file

  STATUSES = %w[queued transcribing writing_notes done failed].freeze
  ACCEPTED_EXTENSIONS = %w[.mp3 .m4a .wav .webm .ogg].freeze
  DEFAULT_MAX_MB = 200

  validates :status, inclusion: { in: STATUSES }

  # @return [Integer] largest upload accepted, in bytes (HIVEMIND_AUDIO_MAX_MB)
  def self.max_bytes
    Integer(ENV.fetch("HIVEMIND_AUDIO_MAX_MB", DEFAULT_MAX_MB)).megabytes
  end

  # @param filename [String]
  # @return [Boolean] true when the file type is one we can transcribe
  def self.accepted_filename?(filename)
    File.extname(filename.to_s).downcase.in?(ACCEPTED_EXTENSIONS)
  end

  # @return [String] the progress line shown in the chat for the current status
  def progress_text
    case status
    when "queued" then "Got your recording. Waiting for its turn."
    when "transcribing" then "Listening to the recording and typing it out."
    when "writing_notes" then "Writing up the notes."
    when "done" then "Notes are ready."
    else "Could not turn the recording into notes. #{error}".strip
    end
  end
end
