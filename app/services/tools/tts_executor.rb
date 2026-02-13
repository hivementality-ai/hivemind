# frozen_string_literal: true

require "net/http"
require "json"

module Tools
  class TtsExecutor < BaseExecutor
    # Text-to-speech via OpenAI TTS API
    VOICES = %w[alloy echo fable onyx nova shimmer].freeze

    def call
      text = input["text"].to_s.strip
      voice = input["voice"].to_s.strip.presence || "nova"
      voice = "nova" unless VOICES.include?(voice)

      return ServiceResponse.failure(error: "No text provided") if text.empty?
      return ServiceResponse.failure(error: "Text too long (max 4096 chars)") if text.length > 4096

      api_key = resolve_openai_key
      return ServiceResponse.failure(error: "OpenAI API key not configured") unless api_key

      uri = URI("https://api.openai.com/v1/audio/speech")
      body = {
        model: "tts-1",
        input: text,
        voice: voice,
        response_format: "mp3"
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      response = http.request(req)

      if response.is_a?(Net::HTTPSuccess)
        # Save audio file
        filename = "tts_#{SecureRandom.hex(6)}.mp3"
        filepath = Rails.root.join("tmp", filename)
        File.binwrite(filepath, response.body)

        ServiceResponse.success(data: {
          output: "Audio generated: #{filename} (#{response.body.size} bytes, voice: #{voice})\nPath: #{filepath}",
          exit_code: 0
        })
      else
        error = begin
          JSON.parse(response.body).dig("error", "message")
        rescue StandardError
          response.body.truncate(200)
        end
        ServiceResponse.failure(error: "TTS failed: #{error}")
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "TTS error: #{e.message}")
    end

    private

    def resolve_openai_key
      entry = VaultEntry.find_by(namespace: "providers", key: "openai_api_key")
      entry&.value || ENV["OPENAI_API_KEY"]
    end
  end
end
