# frozen_string_literal: true

require "rails_helper"

RSpec.describe Audio::OpenaiTranscriber do
  let(:transcriber) { described_class.new(base_url: "http://whisper.local:9000/v1", api_key: "sk-test", model: "whisper-1") }
  let(:audio) do
    Tempfile.new([ "clip", ".mp3" ]).tap do |file|
      file.write("fake audio")
      file.close
    end
  end
  let(:url) { "http://whisper.local:9000/v1/audio/transcriptions" }

  it "posts the file with the model and key and returns the text" do
    stub = stub_request(:post, url)
           .with(headers: { "Authorization" => "Bearer sk-test", "Content-Type" => %r{multipart/form-data} }) do |req|
             req.body.include?("whisper-1") && req.body.include?("fake audio") && req.body.include?('filename="clip')
           end
           .to_return(status: 200, body: { text: " Hello team. " }.to_json)

    expect(transcriber.transcribe(audio.path, content_type: "audio/mpeg")).to eq("Hello team.")
    expect(stub).to have_been_requested
  end

  it "explains a rejected key" do
    stub_request(:post, url).to_return(status: 401, body: "{}")

    expect { transcriber.transcribe(audio.path, content_type: "audio/mpeg") }
      .to raise_error(described_class::Failure, /did not accept the API key/)
  end

  it "explains an unreachable server" do
    stub_request(:post, url).to_return(status: 500, body: "boom")

    expect { transcriber.transcribe(audio.path, content_type: "audio/mpeg") }
      .to raise_error(described_class::Failure, /could not be reached or refused/)
  end

  it "explains an unreadable answer" do
    stub_request(:post, url).to_return(status: 200, body: "<html>")

    expect { transcriber.transcribe(audio.path, content_type: "audio/mpeg") }
      .to raise_error(described_class::Failure, /unreadable/)
  end
end
