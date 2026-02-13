# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::ImageExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    # Mock provider configs
    @openai_provider = instance_double(ProviderConfig, adapter_type: 'openai', enabled: true, config: { 'api_key' => 'openai-key' })
    @anthropic_provider = instance_double(ProviderConfig, adapter_type: 'anthropic', enabled: true, config: { 'api_key' => 'anthropic-key' })
  end

  describe '#call' do
    context 'with valid image URL and OpenAI available' do
      let(:input) { { "image" => "https://example.com/image.jpg", "prompt" => "What's in this image?" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(@openai_provider)
        mock_successful_openai_response
      end

      it 'analyzes image with OpenAI' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("This image shows a beautiful landscape with mountains.")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'makes correct OpenAI API request' do
        executor.call
        expect(Net::HTTP).to have_received(:new).with('api.openai.com', 443)
        expect(@mock_request).to have_received(:[]=).with("Authorization", "Bearer openai-key")
        expect(@mock_request).to have_received(:[]=).with("Content-Type", "application/json")
      end

      it 'sends correct request body to OpenAI' do
        executor.call
        body = JSON.parse(@mock_request.body)
        expect(body["model"]).to eq("gpt-5.2")
        expect(body["messages"].first["content"]).to include(
          { "type" => "text", "text" => "What's in this image?" },
          { "type" => "image_url", "image_url" => { "url" => "https://example.com/image.jpg" } }
        )
        expect(body["max_tokens"]).to eq(1000)
      end
    end

    context 'with default prompt' do
      let(:input) { { "image" => "https://example.com/image.jpg" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(@openai_provider)
        mock_successful_openai_response
      end

      it 'uses default prompt when none provided' do
        executor.call
        body = JSON.parse(@mock_request.body)
        expect(body["messages"].first["content"].first["text"]).to eq("Describe this image in detail.")
      end
    end

    context 'with empty prompt' do
      let(:input) { { "image" => "https://example.com/image.jpg", "prompt" => "  " } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(@openai_provider)
        mock_successful_openai_response
      end

      it 'uses default prompt when empty' do
        executor.call
        body = JSON.parse(@mock_request.body)
        expect(body["messages"].first["content"].first["text"]).to eq("Describe this image in detail.")
      end
    end

    context 'with Anthropic fallback' do
      let(:input) { { "image" => "https://example.com/image.jpg", "prompt" => "Analyze this image" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(nil)
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "anthropic", enabled: true).and_return(@anthropic_provider)
        mock_successful_anthropic_response
        mock_image_download
      end

      it 'falls back to Anthropic when OpenAI unavailable' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("I can see a landscape image with mountains and trees.")
      end

      it 'makes correct Anthropic API request' do
        executor.call
        expect(@mock_request).to have_received(:[]=).with("x-api-key", "anthropic-key")
        expect(@mock_request).to have_received(:[]=).with("anthropic-version", "2023-06-01")
      end

      it 'sends image as base64 to Anthropic' do
        executor.call
        body = JSON.parse(@mock_request.body)
        expect(body["model"]).to eq("claude-haiku-4-5")
        expect(body["messages"].first["content"]).to include(
          {
            "type" => "image",
            "source" => {
              "type" => "base64",
              "media_type" => "image/jpeg",
              "data" => Base64.strict_encode64("mock_image_data")
            }
          },
          { "type" => "text", "text" => "Analyze this image" }
        )
      end

      it 'downloads image for Anthropic' do
        executor.call
        expect(Net::HTTP).to have_received(:new).with('example.com', 443)
      end

      context 'with OAuth token' do
        before do
          @anthropic_provider = instance_double(ProviderConfig, adapter_type: 'anthropic', enabled: true, config: { 'api_key' => 'sk-ant-oat-token123' })
          allow(ProviderConfig).to receive(:find_by).with(adapter_type: "anthropic", enabled: true).and_return(@anthropic_provider)
        end

        it 'handles OAuth tokens correctly' do
          executor.call
          expect(@mock_request).to have_received(:delete).with("x-api-key")
          expect(@mock_request).to have_received(:[]=).with("Authorization", "Bearer sk-ant-oat-token123")
          expect(@mock_request).to have_received(:[]=).with("anthropic-beta", "oauth-2025-04-20,claude-code-20250219")
        end
      end
    end

    context 'without image URL' do
      let(:input) { { "prompt" => "Analyze this image" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No image URL provided")
      end
    end

    context 'with empty image URL' do
      let(:input) { { "image" => "  ", "prompt" => "Analyze this image" } }

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No image URL provided")
      end
    end

    context 'without vision providers' do
      let(:input) { { "image" => "https://example.com/image.jpg" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(nil)
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "anthropic", enabled: true).and_return(nil)
      end

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("No vision-capable provider configured (need OpenAI or Anthropic)")
      end
    end

    context 'when OpenAI API fails' do
      let(:input) { { "image" => "https://example.com/image.jpg" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(@openai_provider)
        mock_failed_openai_response
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("OpenAI error: Insufficient quota")
      end
    end

    context 'when Anthropic API fails' do
      let(:input) { { "image" => "https://example.com/image.jpg" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(nil)
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "anthropic", enabled: true).and_return(@anthropic_provider)
        mock_failed_anthropic_response
        mock_image_download
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Anthropic error: Rate limit exceeded")
      end
    end

    context 'when image download fails' do
      let(:input) { { "image" => "https://example.com/invalid-image.jpg" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(nil)
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "anthropic", enabled: true).and_return(@anthropic_provider)
        mock_failed_image_download
      end

      it 'returns failure' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Could not download image")
      end
    end

    context 'when network request raises exception' do
      let(:input) { { "image" => "https://example.com/image.jpg" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(@openai_provider)
        allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(SocketError.new("Network unreachable"))
      end

      it 'returns failure with exception message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Image analysis failed: Network unreachable")
      end
    end

    context 'when API key resolution fails' do
      let(:input) { { "image" => "https://example.com/image.jpg" } }

      before do
        provider = instance_double(ProviderConfig, adapter_type: 'openai', enabled: true, config: nil)
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(provider)
        allow(VaultEntry).to receive(:find_by).and_return(nil)
        allow(executor).to receive(:resolve_api_key).and_return(nil)
      end

      it 'returns failure when no API key found' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("OpenAI API key not found")
      end
    end

    context 'with different image content types' do
      let(:input) { { "image" => "https://example.com/image.png" } }

      before do
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "openai", enabled: true).and_return(nil)
        allow(ProviderConfig).to receive(:find_by).with(adapter_type: "anthropic", enabled: true).and_return(@anthropic_provider)
        mock_successful_anthropic_response
        
        # Mock PNG image download
        response = instance_double(Net::HTTPOK, is_a?: Net::HTTPSuccess, body: "mock_png_data")
        response.define_singleton_method(:[]) { |key| key == "content-type" ? "image/png; charset=utf-8" : nil }
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
      end

      it 'handles different image formats' do
        executor.call
        body = JSON.parse(@mock_request.body)
        image_content = body["messages"].first["content"].find { |c| c["type"] == "image" }
        expect(image_content["source"]["media_type"]).to eq("image/png")
      end
    end
  end

  describe '#resolve_api_key' do
    let(:provider) { instance_double(ProviderConfig, config: { 'api_key' => 'provider-key' }) }

    it 'returns provider config key when available' do
      key = executor.send(:resolve_api_key, provider, 'openai')
      expect(key).to eq('provider-key')
    end

    context 'when provider config is nil' do
      let(:provider) { instance_double(ProviderConfig, config: nil) }

      before do
        create(:vault_entry, namespace: 'providers', key: 'openai_api_key', value: 'vault-key')
      end

      it 'falls back to vault entry' do
        key = executor.send(:resolve_api_key, provider, 'openai')
        expect(key).to eq('vault-key')
      end
    end

    context 'when both provider config and vault fail' do
      let(:provider) { instance_double(ProviderConfig, config: nil) }

      it 'returns nil' do
        key = executor.send(:resolve_api_key, provider, 'openai')
        expect(key).to be_nil
      end
    end
  end

  describe '#download_image' do
    context 'with successful download' do
      before do
        mock_image_download
      end

      it 'returns base64 encoded image data' do
        result = executor.send(:download_image, 'https://example.com/image.jpg')
        expect(result[:base64]).to eq(Base64.strict_encode64("mock_image_data"))
        expect(result[:media_type]).to eq("image/jpeg")
      end
    end

    context 'with failed download' do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(SocketError)
      end

      it 'returns nil on failure' do
        result = executor.send(:download_image, 'https://example.com/image.jpg')
        expect(result).to be_nil
      end
    end

    context 'with HTTP error response' do
      before do
        response = instance_double(Net::HTTPNotFound, is_a?: false)
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
      end

      it 'returns nil for non-success responses' do
        result = executor.send(:download_image, 'https://example.com/image.jpg')
        expect(result).to be_nil
      end
    end
  end

  private

  def mock_successful_openai_response
    @mock_http = instance_double(Net::HTTP)
    @mock_request = instance_double(Net::HTTP::Post)
    response = instance_double(Net::HTTPOK, 
      body: JSON.generate({
        "choices" => [{"message" => {"content" => "This image shows a beautiful landscape with mountains."}}]
      })
    )

    allow(Net::HTTP).to receive(:new).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
    allow(@mock_http).to receive(:request).and_return(response)

    allow(Net::HTTP::Post).to receive(:new).and_return(@mock_request)
    allow(@mock_request).to receive(:[]=)
    allow(@mock_request).to receive(:body=)
    allow(@mock_request).to receive(:body).and_return('{}')
  end

  def mock_failed_openai_response
    @mock_http = instance_double(Net::HTTP)
    @mock_request = instance_double(Net::HTTP::Post)
    response = instance_double(Net::HTTPBadRequest, 
      body: JSON.generate({"error" => {"message" => "Insufficient quota"}})
    )

    allow(Net::HTTP).to receive(:new).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
    allow(@mock_http).to receive(:request).and_return(response)

    allow(Net::HTTP::Post).to receive(:new).and_return(@mock_request)
    allow(@mock_request).to receive(:[]=)
    allow(@mock_request).to receive(:body=)
  end

  def mock_successful_anthropic_response
    @mock_request = instance_double(Net::HTTP::Post)
    response = instance_double(Net::HTTPOK, 
      body: JSON.generate({
        "content" => [{"text" => "I can see a landscape image with mountains and trees."}]
      })
    )

    allow(Net::HTTP).to receive(:new).with('api.anthropic.com', 443).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
    allow(@mock_http).to receive(:request).and_return(response)

    allow(Net::HTTP::Post).to receive(:new).and_return(@mock_request)
    allow(@mock_request).to receive(:[]=)
    allow(@mock_request).to receive(:delete)
    allow(@mock_request).to receive(:body=)
    allow(@mock_request).to receive(:body).and_return('{}')
  end

  def mock_failed_anthropic_response
    @mock_request = instance_double(Net::HTTP::Post)
    response = instance_double(Net::HTTPTooManyRequests, 
      body: JSON.generate({"error" => {"message" => "Rate limit exceeded"}})
    )

    allow(Net::HTTP).to receive(:new).with('api.anthropic.com', 443).and_return(@mock_http)
    allow(@mock_http).to receive(:use_ssl=)
    allow(@mock_http).to receive(:open_timeout=)
    allow(@mock_http).to receive(:read_timeout=)
    allow(@mock_http).to receive(:request).and_return(response)

    allow(Net::HTTP::Post).to receive(:new).and_return(@mock_request)
    allow(@mock_request).to receive(:[]=)
    allow(@mock_request).to receive(:delete)
    allow(@mock_request).to receive(:body=)
  end

  def mock_image_download
    response = instance_double(Net::HTTPOK, is_a?: Net::HTTPSuccess, body: "mock_image_data")
    response.define_singleton_method(:[]) { |key| key == "content-type" ? "image/jpeg" : nil }
    
    allow(Net::HTTP).to receive(:new).with('example.com', 443).and_return(instance_double(Net::HTTP))
    allow_any_instance_of(Net::HTTP).to receive(:use_ssl=)
    allow_any_instance_of(Net::HTTP).to receive(:open_timeout=)
    allow_any_instance_of(Net::HTTP).to receive(:read_timeout=)
    allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
  end

  def mock_failed_image_download
    allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(SocketError)
  end
end