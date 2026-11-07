# frozen_string_literal: true

require "faraday/multipart"

module Audio
  # Speech-to-text over an OpenAI-style /audio/transcriptions endpoint, which
  # OpenAI and local whisper servers both speak.
  class OpenaiTranscriber
    OPENAI_URL = "https://api.openai.com"
    Failure = Class.new(StandardError)

    # @param base_url [String] server root, with or without a trailing /v1
    # @param api_key [String, nil]
    # @param model [String]
    def initialize(base_url:, api_key:, model:)
      @base_url = base_url.to_s.chomp("/").delete_suffix("/v1")
      @api_key = api_key
      @model = model
    end

    # @param path [String] audio file on disk
    # @param content_type [String]
    # @return [String] the transcript
    # @raise [Failure] with a plain-words reason
    def transcribe(path, content_type:)
      response = connection.post("/v1/audio/transcriptions",
                                 file: Faraday::Multipart::FilePart.new(path, content_type),
                                 model: @model, response_format: "json")
      JSON.parse(response.body.to_s)["text"].to_s.strip
    rescue Faraday::UnauthorizedError
      raise Failure, "The speech service did not accept the API key."
    rescue Faraday::Error => e
      raise Failure, "The speech service could not be reached or refused the file (#{e.message.truncate(80)})."
    rescue JSON::ParserError
      raise Failure, "The speech service sent back something unreadable."
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |f|
        f.request :multipart
        f.request :authorization, "Bearer", @api_key if @api_key.present?
        f.response :raise_error
        f.options.open_timeout = 10
        f.options.timeout = 600
        f.adapter Faraday.default_adapter
      end
    end
  end
end
