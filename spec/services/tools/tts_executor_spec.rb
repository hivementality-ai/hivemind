# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::TtsExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    allow(SecureRandom).to receive(:hex).and_return('abc123')
    allow(Rails).to receive(:root).and_return(Pathname.new('/app'))
    allow(File).to receive(:binwrite)
    
    # Mock OpenAI API key
    allow(executor).to receive(:resolve_openai_key).and_return('sk-test-key')
  end

  describe '#call' do
    context 'with valid text input' do
      let(:input) { { "text" => "Hello, world! This is a test message." } }

      before do
        mock_successful_tts_response
      end

      it 'generates audio successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Audio generated: tts_abc123.mp3")
        expect(result.data[:output]).to include("1024 bytes, voice: nova")
        expect(result.data[:output]).to include("Path: /app/tmp/tts_abc123.mp3")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'makes correct API request' do
        executor.call
        expect(Net::HTTP).to have_received(:new).with('api.openai.com', 443)
        expect(@mock_request).to have_received(:[]=).with("Authorization", "Bearer sk-test-key")
        expect(@mock_request).to have_received(:[]=).with("Content-Type", "application/json")
      end

      it 'sends correct request body' do
        executor.call
        body = JSON.parse(@mock_request.body)
        expect(body).to eq({
          "model" => "tts-1",
          "input" => "Hello, world! This is a test message.",
          "voice" => "nova",
          "response_format" => "mp3"
        })
      end

      it 'saves audio file' do
        executor.call
        expect(File).to have_received(:binwrite).with(
          Pathname.new('/app/tmp/tts_abc123.mp3'),
          'mock_audio_data'
        )
      end

      it 'configures HTTP timeouts' do
        executor.call
        expect(@mock_http).to have_received(:open_timeout=).with(10)
        expect(@mock_http).to have_received(:read_timeout=).with(30)
      end
    end

    context 'with custom voice' do
      let(:input) { { "text" => "Hello with custom voice", "voice" => "alloy" } }

      before do
        mock_successful_tts_response
      end

      it 'uses specified voice' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("voice: alloy")
      end

      it 'sends voice in request body' do
        executor.call
        body = JSON.parse(@mock_request.body)
        expect(body["voice"]).to eq("alloy")
      end
    end

    context 'with invalid voice' do
      let(:input) { { "text" => "Hello with invalid voice", "voice" => "invalid_voice" } }

      before do
        mock_successful_tts_response
      end

      it 'falls back to nova voice' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("voice: nova")
      end
    end

    context 'with empty voice' do
      let(:input) { { "text" => "Hello with empty voice", "voice" => "  " } }

      before do
        mock_successful_tts_response
      end

      it 'uses default nova voice' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("voice: nova")
      end
    end

    context 'without voice specified' do
      let(:input) { { "text" => "Hello without voice" } }

      before do
        mock_successful_tts_response
      end

      it 'defaults to nova voice' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("voice: nova")
      end
    end

    context 'without text' do
      let(:input) { {} }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No text provided")
      end
    end

    context 'with empty text' do
      let(:input) { { "text" => "  " } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No text provided")
      end
    end

    context 'with text too long' do
      let(:long_text) { 'a' * 4097 }
      let(:input) { { "text" => long_text } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Text too long (max 4096 chars)")
      end
    end

    context 'with text at maximum length' do
      let(:max_text) { 'a' * 4096 }
      let(:input) { { "text" => max_text } }

      before do
        mock_successful_tts_response
      end

      it 'accepts text at maximum length' do
        result = executor.call
        expect(result).to be_success
      end
    end

    context 'without OpenAI API key' do
      let(:input) { { "text" => "Hello, world!" } }

      before do
        allow(executor).to receive(:resolve_openai_key).and_return(nil)
      end

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("OpenAI API key not configured")
      end
    end

    context 'when API request fails' do
      let(:input) { { "text" => "Hello, world!" } }

      before do
        mock_failed_tts_response
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("TTS failed: Insufficient quota")
      end
    end

    context 'when API returns non-JSON error' do
      let(:input) { { "text" => "Hello, world!" } }

      before do
        response = instance_double(Net::HTTPBadRequest, is_a?: false, body: "Rate limit exceeded")
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
      end

      it 'truncates and returns error body' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("TTS failed: Rate limit exceeded")
      end
    end

    context 'when network request raises exception' do
      let(:input) { { "text" => "Hello, world!" } }

      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(SocketError.new("Network unreachable"))
      end

      it 'returns failure with exception message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("TTS error: Network unreachable")
      end
    end

    context 'when file write fails' do
      let(:input) { { "text" => "Hello, world!" } }

      before do
        mock_successful_tts_response
        allow(File).to receive(:binwrite).and_raise(Errno::EACCES.new("Permission denied"))
      end

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("TTS error: Permission denied")
      end
    end

    context 'with all supported voices' do
      Tools::TtsExecutor::VOICES.each do |voice|
        context "with #{voice} voice" do
          let(:input) { { "text" => "Hello", "voice" => voice } }

          before do
            mock_successful_tts_response
          end

          it "accepts #{voice} voice" do
            result = executor.call
            expect(result).to be_success
            expect(result.data[:output]).to include("voice: #{voice}")
          end
        end
      end
    end

    context 'with large response body' do
      let(:input) { { "text" => "Hello, world!" } }
      let(:large_audio_data) { 'x' * 1_000_000 }

      before do
        response = instance_double(Net::HTTPOK, is_a?: Net::HTTPSuccess, body: large_audio_data)
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
      end

      it 'handles large audio files' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("1000000 bytes")
      end
    end

    context 'with special characters in text' do
      let(:input) { { "text" => "Hello! How are you? I'm fine. 50% complete." } }

      before do
        mock_successful_tts_response
      end

      it 'handles special characters' do
        result = executor.call
        expect(result).to be_success
      end
    end

    context 'with timeout during request' do
      let(:input) { { "text" => "Hello, world!" } }

      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Net::ReadTimeout.new("Request timeout"))
      end

      it 'returns failure with timeout error' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("TTS error: Request timeout")
      end
    end
  end

  describe '#resolve_openai_key' do
    context 'with vault entry' do
      before do
        create(:vault_entry, namespace: 'providers', key: 'openai_api_key', value: 'vault-key-123')
      end

      it 'returns vault key' do
        key = executor.send(:resolve_openai_key)
        expect(key).to eq('vault-key-123')
      end
    end

    context 'with environment variable' do
      before do
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return('env-key-456')
      end

      it 'falls back to environment variable' do
        key = executor.send(:resolve_openai_key)
        expect(key).to eq('env-key-456')
      end
    end

    context 'with both vault and env' do
      before do
        create(:vault_entry, namespace: 'providers', key: 'openai_api_key', value: 'vault-key-123')
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return('env-key-456')
      end

      it 'prefers vault key' do
        key = executor.send(:resolve_openai_key)
        expect(key).to eq('vault-key-123')
      end
    end

    context 'with neither vault nor env' do
      it 'returns nil' do
        key = executor.send(:resolve_openai_key)
        expect(key).to be_nil
      end
    end
  end

  private

  def mock_successful_tts_response
    @mock_http = instance_double(Net::HTTP)
    @mock_request = instance_double(Net::HTTP::Post)
    response = instance_double(Net::HTTPOK, is_a?: Net::HTTPSuccess, body: 'mock_audio_data')

    allow(Net::HTTP).to receive(:new).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
    allow(@mock_http).to receive(:request).and_return(response)

    allow(Net::HTTP::Post).to receive(:new).and_return(@mock_request)
    allow(@mock_request).to receive(:[]=)
    allow(@mock_request).to receive(:body=)
    allow(@mock_request).to receive(:body).and_return('{"model":"tts-1","input":"Hello, world! This is a test message.","voice":"nova","response_format":"mp3"}')
  end

  def mock_failed_tts_response
    @mock_http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPBadRequest, 
      is_a?: false, 
      body: '{"error":{"message":"Insufficient quota"}}'
    )

    allow(Net::HTTP).to receive(:new).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
    allow(@mock_http).to receive(:request).and_return(response)

    allow(Net::HTTP::Post).to receive(:new).and_return(instance_double(Net::HTTP::Post, :[]=: nil, body=: nil))
  end
end