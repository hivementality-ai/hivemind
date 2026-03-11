# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::SttExecutor do
  let(:agent) { create(:agent) }
  let(:config) { {} }

  def execute(input)
    described_class.new(input: input, config: config, agent: agent).call
  end

  describe "#call" do
    context "validation" do
      it "requires file_path" do
        result = execute({})
        expect(result.success?).to be(false)
        expect(result.error).to include("file_path is required")
      end

      it "returns failure for missing file" do
        result = execute("file_path" => "/nonexistent/audio.mp3")
        expect(result.success?).to be(false)
        expect(result.error).to include("File not found")
      end

      it "rejects unsupported formats" do
        Tempfile.create([ "test", ".exe" ]) do |f|
          result = execute("file_path" => f.path)
          expect(result.success?).to be(false)
          expect(result.error).to include("Unsupported audio format")
        end
      end

      it "rejects files over 25MB" do
        Tempfile.create([ "test", ".mp3" ]) do |f|
          allow(File).to receive(:size).with(f.path).and_return(30 * 1024 * 1024)
          result = execute("file_path" => f.path)
          expect(result.success?).to be(false)
          expect(result.error).to include("File too large")
        end
      end
    end

    context "API transcription" do
      it "sends to Whisper API and returns transcription" do
        Tempfile.create([ "test", ".mp3" ]) do |f|
          f.write("fake audio data")
          f.flush

          allow(VaultEntry).to receive(:find_by).and_return(double(value: "sk-test-key"))

          stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
            .to_return(status: 200, body: { text: "Hello world" }.to_json)

          result = execute("file_path" => f.path)
          expect(result.success?).to be(true)
          expect(result.data[:transcription]).to eq("Hello world")
          expect(result.data[:output]).to include("Transcription:")
        end
      end

      it "handles API errors" do
        Tempfile.create([ "test", ".wav" ]) do |f|
          f.write("fake audio")
          f.flush

          allow(VaultEntry).to receive(:find_by).and_return(double(value: "sk-test-key"))

          stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
            .to_return(status: 400, body: { error: { message: "Invalid file" } }.to_json)

          result = execute("file_path" => f.path)
          expect(result.success?).to be(false)
          expect(result.error).to include("Whisper API failed")
        end
      end
    end

    context "local fallback" do
      it "falls back to local whisper when no API key" do
        Tempfile.create([ "test", ".mp3" ]) do |f|
          f.write("fake audio")
          f.flush

          allow(VaultEntry).to receive(:find_by).and_return(nil)
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)

          allow_any_instance_of(described_class).to receive(:find_whisper_binary).and_return(nil)

          result = execute("file_path" => f.path)
          expect(result.success?).to be(false)
          expect(result.error).to include("whisper CLI not found")
        end
      end
    end

    context "supported formats" do
      %w[mp3 wav ogg flac webm m4a mp4].each do |ext|
        it "accepts .#{ext} files" do
          Tempfile.create([ "test", ".#{ext}" ]) do |f|
            f.write("fake audio")
            f.flush

            allow(VaultEntry).to receive(:find_by).and_return(double(value: "sk-test"))
            stub_request(:post, "https://api.openai.com/v1/audio/transcriptions")
              .to_return(status: 200, body: { text: "test" }.to_json)

            result = execute("file_path" => f.path)
            expect(result.success?).to be(true)
          end
        end
      end
    end
  end
end
