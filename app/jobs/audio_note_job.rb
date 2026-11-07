# frozen_string_literal: true

# Turns an uploaded recording into a transcript and notes: transcribes it
# (in pieces when it is large), writes the notes, saves the transcript to the
# agent's library, posts the notes in the chat, and deletes the audio unless
# the person chose to keep it. Progress is posted to the chat as it goes.
class AudioNoteJob < ApplicationJob
  queue_as :default

  discard_on(StandardError) { |job, error| job.report_failure(job.arguments.first, error) }

  # @param audio_note_id [Integer]
  def perform(audio_note_id)
    note = AudioNote.find_by(id: audio_note_id)
    return unless note&.file&.attached?

    transcriber = Audio::SpeechToText.adapter
    return fail_note(note, Audio::SpeechToText::NOT_SET_UP) unless transcriber

    advance(note, "transcribing")
    note.update!(transcript: transcribe(note, transcriber))
    raise Audio::OpenaiTranscriber::Failure, "No speech could be heard in the recording." if note.transcript.blank?

    note.file.purge unless note.keep_recording
    note.update!(knowledge_document: save_to_library(note))
    advance(note, "writing_notes")
    note.update!(notes: Audio::NotesWriter.new(note.agent).call(note.transcript))
    finish(note)
  rescue Audio::OpenaiTranscriber::Failure, Audio::Splitter::Failure, Audio::NotesWriter::Failure => e
    fail_note(note, e.message)
  end

  # @param audio_note_id [Integer]
  # @param error [Exception]
  def report_failure(audio_note_id, error)
    Rails.logger.error("[AudioNoteJob] note=#{audio_note_id} failed: #{error.message}")
    note = AudioNote.find_by(id: audio_note_id)
    fail_note(note, "Something went wrong on our side. Try again in a minute.") if note
  end

  private

  def transcribe(note, transcriber)
    note.file.open do |tempfile|
      parts = []
      Audio::Splitter.each_piece(tempfile.path) do |piece|
        parts << transcriber.transcribe(piece, content_type: note.content_type.presence || "audio/mpeg")
      end
      parts.reject(&:blank?).join("\n\n")
    end
  end

  def finish(note)
    note.session.append_transcript({ "role" => "assistant", "content" => note.notes })
    advance(note, "done", broadcast: false)
    broadcast(note.session, { type: "done", content: note.notes })
  end

  def save_to_library(note)
    dir = Rails.root.join("storage", "knowledge_documents")
    FileUtils.mkdir_p(dir)
    path = dir.join("audio-#{SecureRandom.hex(8)}.txt")
    File.write(path, note.transcript)
    document = KnowledgeDocument.create!(
      agent: note.agent, title: "Recording: #{note.filename}".truncate(200), source_type: "text",
      source_url: path.to_s, metadata: { audio_note_id: note.id }
    )
    KnowledgeIngestionJob.perform_later(document.id)
    document
  end

  def advance(note, status, broadcast: true)
    note.update!(status: status)
    broadcast(note.session, { type: "notice", content: note.progress_text }) if broadcast
  end

  def fail_note(note, reason)
    note.update!(status: "failed", error: reason)
    note.file.purge if note.file.attached? && !note.keep_recording
    broadcast(note.session, { type: "error", content: note.progress_text })
  end

  def broadcast(session, payload)
    ActionCable.server.broadcast("session_#{session.id}", payload)
  end
end
