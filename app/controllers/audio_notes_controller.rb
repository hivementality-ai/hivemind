# frozen_string_literal: true

# Accepts a recording dropped or recorded in a chat and hands it to
# AudioNoteJob, so the request never waits on transcription.
class AudioNotesController < ApplicationController
  before_action :set_session

  # POST /sessions/:session_id/audio_notes
  def create
    return render_not_set_up unless Audio::SpeechToText.provider_config

    upload = params[:file]
    return render_error("Pick an audio file or record one first.") unless upload.respond_to?(:original_filename)
    unless AudioNote.accepted_filename?(upload.original_filename)
      return render_error("That file type is not supported. Use mp3, m4a, wav, webm or ogg.")
    end
    if upload.size > AudioNote.max_bytes
      return render_error("That recording is too big. The limit is #{AudioNote.max_bytes / 1.megabyte} MB.")
    end

    note = build_note(upload)
    ActionCable.server.broadcast("session_#{@session.id}", { type: "notice", content: note.progress_text })
    AudioNoteJob.perform_later(note.id)
    render json: { id: note.id, status: note.status }, status: :accepted
  end

  private

  def set_session
    @session = Session.find(params[:session_id])
  end

  def build_note(upload)
    note = @session.audio_notes.create!(
      agent: @session.agent, filename: upload.original_filename, content_type: upload.content_type,
      byte_size: upload.size, keep_recording: ActiveModel::Type::Boolean.new.cast(params[:keep_recording]) || false
    )
    note.file.attach(upload)
    note
  end

  def render_not_set_up
    render json: { error: Audio::SpeechToText::NOT_SET_UP, settings_url: providers_path }, status: :unprocessable_entity
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
