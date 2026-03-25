# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "base64"

module Tools
  class ImageExecutor < BaseExecutor
    # Analyze an image using a vision-capable model (OpenAI GPT-5.2 or Anthropic Claude)
    def call
      image_url = input["image"].to_s.strip
      prompt = input["prompt"].to_s.strip.presence || "Describe this image in detail."

      return ServiceResponse.failure(error: "No image URL provided") if image_url.empty?

      # Try OpenAI first (gpt-5.4), fall back to Anthropic
      provider = ProviderConfig.find_by(adapter_type: "openai", enabled: true)
      if provider
        analyze_with_openai(image_url, prompt, provider)
      else
        provider = ProviderConfig.find_by(adapter_type: "anthropic", enabled: true)
        if provider
          analyze_with_anthropic(image_url, prompt, provider)
        else
          ServiceResponse.failure(error: "No vision-capable provider configured (need OpenAI or Anthropic)")
        end
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "Image analysis failed: #{e.message}")
    end

    private

    def analyze_with_openai(image_url, prompt, provider)
      api_key = resolve_api_key(provider, "openai")
      return ServiceResponse.failure(error: "OpenAI API key not found") unless api_key

      uri = URI("https://api.openai.com/v1/chat/completions")
      body = {
        model: "gpt-5.4",
        messages: [ {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: { url: image_url } }
          ]
        } ],
        max_tokens: 1000
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 60

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      response = http.request(req)
      data = JSON.parse(response.body)

      if data["choices"]&.first
        content = data.dig("choices", 0, "message", "content")
        ServiceResponse.success(data: { output: content, exit_code: 0 })
      else
        ServiceResponse.failure(error: "OpenAI error: #{data["error"]&.dig("message") || response.body.truncate(200)}")
      end
    end

    def analyze_with_anthropic(image_url, prompt, provider)
      api_key = resolve_api_key(provider, "anthropic")
      return ServiceResponse.failure(error: "Anthropic API key not found") unless api_key

      # Download image and base64 encode for Anthropic
      image_data = download_image(image_url)
      return ServiceResponse.failure(error: "Could not download image") unless image_data

      uri = URI("https://api.anthropic.com/v1/messages")
      body = {
        model: "claude-haiku-4-5",
        max_tokens: 1000,
        messages: [ {
          role: "user",
          content: [
            {
              type: "image",
              source: {
                type: "base64",
                media_type: image_data[:media_type],
                data: image_data[:base64]
              }
            },
            { type: "text", text: prompt }
          ]
        } ]
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 60

      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = api_key
      req["anthropic-version"] = "2023-06-01"
      req["Content-Type"] = "application/json"

      # Handle OAuth tokens
      if api_key.start_with?("sk-ant-oat")
        req.delete("x-api-key")
        req["Authorization"] = "Bearer #{api_key}"
        req["anthropic-beta"] = "oauth-2025-04-20,claude-code-20250219"
      end

      req.body = body.to_json
      response = http.request(req)
      data = JSON.parse(response.body)

      if data["content"]&.first
        content = data.dig("content", 0, "text")
        ServiceResponse.success(data: { output: content, exit_code: 0 })
      else
        ServiceResponse.failure(error: "Anthropic error: #{data["error"]&.dig("message") || response.body.truncate(200)}")
      end
    end

    def download_image(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 15

      response = http.request(Net::HTTP::Get.new(uri))
      return nil unless response.is_a?(Net::HTTPSuccess)

      content_type = response["content-type"] || "image/jpeg"
      media_type = content_type.split(";").first.strip

      {
        base64: Base64.strict_encode64(response.body),
        media_type: media_type
      }
    rescue StandardError
      nil
    end

    def resolve_api_key(provider, type)
      # Check provider config first
      key = provider.config&.dig("api_key")
      return key if key.present?

      # Check vault
      entry = VaultEntry.find_by(namespace: "providers", key: "#{type}_api_key")
      entry&.value
    rescue StandardError
      nil
    end
  end
end
