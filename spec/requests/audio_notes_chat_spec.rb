# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audio to notes in the chat", type: :request do
  let(:session) { create(:session) }

  before { sign_in create(:user, :owner) }

  it "offers choosing a file, recording, and keeping the recording on the chat page" do
    get session_path(session)

    expect(response.body).to include(%(data-controller="audio-notes"), "Choose file", "Record", "Keep the recording")
    expect(response.body).to include(session_audio_notes_path(session))
    expect(response.body).to include(".mp3,.m4a,.wav,.webm,.ogg")
  end

  describe "saving the finished notes as a page" do
    let(:note) { create(:audio_note, session: session, agent: session.agent) }
    let(:notes) { "## Summary\nShip it on Friday." }

    before do
      transcriber = instance_double(Audio::OpenaiTranscriber, transcribe: "Hello team.")
      allow(Audio::SpeechToText).to receive(:adapter).and_return(transcriber)
      allow(Audio::NotesWriter).to receive(:new).and_return(instance_double(Audio::NotesWriter, call: notes))
      allow(Audio::Splitter).to receive(:each_piece).and_yield("/tmp/a.mp3")
      allow(KnowledgeIngestionJob).to receive(:perform_later)
      allow(ActionCable.server).to receive(:broadcast)
      AudioNoteJob.perform_now(note.id)
    end

    it "shows a Save as page button for the notes message after a reload" do
      get session_path(session)

      index = session.reload.transcript.rindex { |m| m["content"] == notes }
      expect(response.body).to include("Save as page")
      expect(response.body).to include(%(name="message_index" value="#{index}"))
    end

    it "creates a saved page holding the notes" do
      index = session.reload.transcript.rindex { |m| m["content"] == notes }

      expect { post saved_pages_path, params: { session_id: session.id, message_index: index } }
        .to change(SavedPage, :count).by(1)

      expect(SavedPage.last).to have_attributes(body: notes, session: session)
    end
  end
end
