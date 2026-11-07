# frozen_string_literal: true

require "rails_helper"

RSpec.describe AudioNoteJob, type: :job do
  let(:note) { create(:audio_note, keep_recording: keep) }
  let(:keep) { false }
  let(:transcriber) { instance_double(Audio::OpenaiTranscriber) }
  let(:writer) { instance_double(Audio::NotesWriter, call: "## Summary\nShip it.") }
  let(:broadcasts) { [] }

  before do
    allow(Audio::SpeechToText).to receive(:adapter).and_return(transcriber)
    allow(transcriber).to receive(:transcribe).and_return("Hello team.")
    allow(Audio::NotesWriter).to receive(:new).and_return(writer)
    allow(KnowledgeIngestionJob).to receive(:perform_later)
    allow(ActionCable.server).to receive(:broadcast) { |channel, payload| broadcasts << [ channel, payload ] }
    allow(Audio::Splitter).to receive(:each_piece).and_yield("/tmp/a.mp3")
  end

  it "transcribes, saves the transcript to the library, and posts the notes in the chat" do
    described_class.perform_now(note.id)

    note.reload
    expect(note.status).to eq("done")
    expect(note.transcript).to eq("Hello team.")
    expect(note.notes).to eq("## Summary\nShip it.")
    expect(note.knowledge_document).to have_attributes(agent: note.agent, source_type: "text", title: "Recording: standup.mp3")
    expect(File.read(note.knowledge_document.source_url)).to eq("Hello team.")
    expect(KnowledgeIngestionJob).to have_received(:perform_later).with(note.knowledge_document.id)
    expect(note.session.reload.transcript.last).to include("role" => "assistant", "content" => "## Summary\nShip it.")
  end

  it "posts progress to the chat in order, ending with the notes" do
    described_class.perform_now(note.id)

    payloads = broadcasts.map(&:last)
    expect(payloads.pluck(:content)).to eq([
      "Listening to the recording and typing it out.", "Writing up the notes.", "## Summary\nShip it."
    ])
    expect(payloads.pluck(:type)).to eq(%w[notice notice audio_notes])
    expect(broadcasts.map(&:first).uniq).to eq([ "session_#{note.session_id}" ])
  end

  it "deletes the recording after transcription succeeds" do
    described_class.perform_now(note.id)

    expect(note.reload.file).not_to be_attached
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  context "when the person ticked keep the recording" do
    let(:keep) { true }

    it "keeps the audio" do
      described_class.perform_now(note.id)

      expect(note.reload.file).to be_attached
    end
  end

  it "stitches the pieces of a long recording in order" do
    allow(Audio::Splitter).to receive(:each_piece).and_yield("/tmp/1.mp3").and_yield("/tmp/2.mp3")
    allow(transcriber).to receive(:transcribe).with("/tmp/1.mp3", anything).and_return("First half.")
    allow(transcriber).to receive(:transcribe).with("/tmp/2.mp3", anything).and_return("Second half.")

    described_class.perform_now(note.id)

    expect(note.reload.transcript).to eq("First half.\n\nSecond half.")
  end

  it "sends the finished notes as their own message type so a live reply stream is not touched" do
    described_class.perform_now(note.id)

    payloads = broadcasts.map(&:last)
    expect(payloads.last).to eq(type: "audio_notes", content: "## Summary\nShip it.")
    expect(payloads.pluck(:type)).not_to include("done", "error")
  end

  it "fails with a settings pointer when no speech-to-text is set up, and still deletes the audio" do
    allow(Audio::SpeechToText).to receive(:adapter).and_return(nil)

    described_class.perform_now(note.id)

    note.reload
    expect(note.status).to eq("failed")
    expect(note.error).to eq(Audio::SpeechToText::NOT_SET_UP)
    expect(note.file).not_to be_attached
    expect(broadcasts.last.last).to include(type: "audio_error", content: include("No speech-to-text is set up"))
  end

  it "fails in plain words when the speech service fails" do
    allow(transcriber).to receive(:transcribe).and_raise(Audio::OpenaiTranscriber::Failure, "The speech service did not accept the API key.")

    described_class.perform_now(note.id)

    expect(note.reload).to have_attributes(status: "failed", error: "The speech service did not accept the API key.")
    expect(writer).not_to have_received(:call)
  end

  it "fails when nothing was said" do
    allow(transcriber).to receive(:transcribe).and_return("")

    described_class.perform_now(note.id)

    expect(note.reload).to have_attributes(status: "failed", error: "No speech could be heard in the recording.")
  end

  it "keeps the saved transcript when writing the notes fails" do
    allow(writer).to receive(:call).and_raise(Audio::NotesWriter::Failure, "No model is available to write the notes.")

    described_class.perform_now(note.id)

    note.reload
    expect(note.status).to eq("failed")
    expect(note.transcript).to eq("Hello team.")
    expect(note.knowledge_document).to be_present
  end

  it "reports an unexpected error as a plain failure instead of retrying" do
    allow(transcriber).to receive(:transcribe).and_raise(RuntimeError, "kaboom")

    described_class.perform_now(note.id)

    expect(note.reload).to have_attributes(status: "failed", error: /Something went wrong/)
  end
end
