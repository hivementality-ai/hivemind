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
end
