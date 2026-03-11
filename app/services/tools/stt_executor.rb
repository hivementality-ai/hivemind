# frozen_string_literal: true

require "net/http"
require "json"

module Tools
  class SttExecutor < BaseExecutor
    SUPPORTED_FORMATS = %w[mp3 mp4 mpeg mpga m4a wav webm ogg flac].freeze
    MAX_FILE_SIZE = 25 * 1024 * 1024

    def call
      file_path = input["file_path"].to_s.strip
      language = input["language"].to_s.strip.presence

      return ServiceResponse.failure(error: "file_path is required") if file_path.empty?
      return ServiceResponse.failure(error: "File not found: #{file_path}") unless File.exist?(file_path)

      ext = File.extname(file_path).delete(".").downcase
      unless SUPPORTED_FORMATS.include?(ext)
        return ServiceResponse.failure(
          error: "Unsupported audio format: .#{ext}. Supported: #{SUPPORTED_FORMATS.join(', ')}"
        )
      end

      file_size = File.size(file_path)
      if file_size > MAX_FILE_SIZE
        return ServiceResponse.failure(
          error: "File too large (#{(file_size / 1024.0 / 1024).round(1)}MB). Max: 25MB"
        )
      end

      api_key = resolve_openai_key
      if api_key
        transcribe_via_api(file_path, language, api_key)
      else
        transcribe_via_local(file_path, language)
      end
    rescue StandardError => e
      ServiceResponse.failure(error: "STT error: #{e.message}")
    end

    private

    def transcribe_via_api(file_path, language, api_key)
      uri = URI("https://api.openai.com/v1/audio/transcriptions")
      boundary = SecureRandom.hex(16)
      body = build_multipart_body(file_path, language, boundary)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 120

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body

      response = http.request(req)

      if response.is_a?(Net::HTTPSuccess)
        result = JSON.parse(response.body)
        text = result["text"].to_s.strip
        ServiceResponse.success(data: { output: "Transcription:\n#{text}", transcription: text })
      else
        error = begin
          JSON.parse(response.body).dig("error", "message")
        rescue StandardError
          response.body.to_s.truncate(200)
        end
        ServiceResponse.failure(error: "Whisper API failed: #{error}")
      end
    end

    def transcribe_via_local(file_path, language)
      whisper_bin = find_whisper_binary
      unless whisper_bin
        return ServiceResponse.failure(
          error: "No OpenAI API key configured and whisper CLI not found. Configure at /integrations"
        )
      end

      cmd = [ whisper_bin, file_path, "--output_format", "txt" ]
      cmd += [ "--language", language ] if language

      stdout, stderr, status = Open3.capture3(*cmd)

      if status.success?
        txt_path = file_path.sub(/\.[^.]+$/, ".txt")
        text = if File.exist?(txt_path)
          File.read(txt_path).strip
        else
          stdout.strip
        end
        ServiceResponse.success(data: {
          output: "Transcription (local whisper):\n#{text}",
          transcription: text
        })
      else
        ServiceResponse.failure(error: "Local whisper failed: #{stderr.truncate(500)}")
      end
    end

    def build_multipart_body(file_path, language, boundary)
      parts = []
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"model\"\r\n\r\n"
      parts << "whisper-1\r\n"

      if language
        parts << "--#{boundary}\r\n"
        parts << "Content-Disposition: form-data; name=\"language\"\r\n\r\n"
        parts << "#{language}\r\n"
      end

      filename = File.basename(file_path)
      mime = audio_mime_type(file_path)
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
      parts << "Content-Type: #{mime}\r\n\r\n"
      parts << File.binread(file_path)
      parts << "\r\n"
      parts << "--#{boundary}--\r\n"
      parts.join
    end

    def audio_mime_type(file_path)
      ext = File.extname(file_path).delete(".").downcase
      case ext
      when "mp3" then "audio/mpeg"
      when "mp4", "m4a" then "audio/mp4"
      when "wav" then "audio/wav"
      when "webm" then "audio/webm"
      when "ogg" then "audio/ogg"
      when "flac" then "audio/flac"
      else "audio/mpeg"
      end
    end

    def find_whisper_binary
      %w[whisper whisper.cpp].each do |name|
        path = `which #{name} 2>/dev/null`.strip
        return path unless path.empty?
      end
      nil
    end

    def resolve_openai_key
      entry = VaultEntry.find_by(namespace: "providers", key: "openai_api_key")
      entry&.value || ENV["OPENAI_API_KEY"]
    end
  end
end
