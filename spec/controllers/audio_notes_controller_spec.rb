# frozen_string_literal: true

require "rails_helper"

RSpec.describe AudioNotesController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:session) { create(:session) }

  before do
    sign_in user
    allow(ActionCable.server).to receive(:broadcast)
    create(:provider_config, :openai, vault_key: nil)
  end

  def upload(name, content_type = "audio/mpeg", body = "audio bytes")
    file = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    file.write(body)
    file.close
    Rack::Test::UploadedFile.new(file.path, content_type, original_filename: name)
  end

  it "stores the recording, queues the job and answers without waiting" do
    expect { post :create, params: { session_id: session.id, file: upload("memo.m4a", "audio/mp4"), keep_recording: "true" } }
      .to have_enqueued_job(AudioNoteJob)

    expect(response).to have_http_status(:accepted)
    note = AudioNote.last
    expect(note).to have_attributes(session: session, agent: session.agent, filename: "memo.m4a", status: "queued", keep_recording: true)
    expect(note.file).to be_attached
    expect(ActionCable.server).to have_received(:broadcast).with("session_#{session.id}", hash_including(type: "notice"))
  end

  it "does not keep the recording unless asked" do
    post :create, params: { session_id: session.id, file: upload("memo.mp3") }

    expect(AudioNote.last.keep_recording).to be false
  end

  it "rejects other file types with a friendly message" do
    post :create, params: { session_id: session.id, file: upload("notes.pdf", "application/pdf") }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to include("mp3, m4a, wav, webm or ogg")
    expect(AudioNote.count).to eq(0)
  end

  it "rejects a file over the size cap" do
    stub_const("ENV", ENV.to_h.merge("HIVEMIND_AUDIO_MAX_MB" => "1"))

    post :create, params: { session_id: session.id, file: upload("big.mp3", "audio/mpeg", "x" * 2.megabytes) }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to include("1 MB")
    expect(AudioNote.count).to eq(0)
  end

  it "asks for a file when none is sent" do
    post :create, params: { session_id: session.id }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "points to provider settings when no speech-to-text is set up" do
    ProviderConfig.delete_all

    post :create, params: { session_id: session.id, file: upload("memo.mp3") }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include("error" => Audio::SpeechToText::NOT_SET_UP, "settings_url" => providers_path)
    expect(AudioNote.count).to eq(0)
  end
end
