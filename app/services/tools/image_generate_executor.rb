# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "stringio"
require "fileutils"

module Tools
  class ImageGenerateExecutor < BaseExecutor
    WORKSPACE_ROOT = "/workspace"
    GENERATED_DIR = File.join(WORKSPACE_ROOT, "generated", "images")
    DEFAULT_SIZE = "1024x1024"
    VALID_SIZES = %w[1024x1024 1792x1024 1024x1792].freeze

    def call
      prompt = input["prompt"].to_s.strip
      size = input["size"].to_s.strip.presence || DEFAULT_SIZE

      return ServiceResponse.failure(error: "No prompt provided") if prompt.empty?
      return ServiceResponse.failure(error: "Invalid size. Must be one of: #{VALID_SIZES.join(', ')}") unless VALID_SIZES.include?(size)

      # Find OpenAI provider
      provider = ProviderConfig.find_by(adapter_type: "openai", enabled: true)
      return ServiceResponse.failure(error: "OpenAI provider not configured") unless provider

      api_key = resolve_api_key(provider)
      return ServiceResponse.failure(error: "OpenAI API key not found") unless api_key

      # Call DALL-E API
      image_url = generate_image(api_key, prompt, size)
      return ServiceResponse.failure(error: "Failed to generate image") unless image_url

      # Download image
      image_data = download_image(image_url)
      return ServiceResponse.failure(error: "Failed to download generated image") unless image_data

      # Save to workspace
      FileUtils.mkdir_p(GENERATED_DIR)
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "dalle_#{timestamp}.png"
      filepath = File.join(GENERATED_DIR, filename)
      File.binwrite(filepath, image_data)

      # Create ChatAttachment
      session = resolve_session
      return ServiceResponse.failure(error: "No session context available") unless session

      attachment = session.chat_attachments.create!(
        content_type: "image/png",
        filename: filename,
        byte_size: image_data.bytesize
      )

      # Attach file via ActiveStorage
      attachment.file.attach(
        io: StringIO.new(image_data),
        filename: filename,
        content_type: "image/png"
      )

      # Broadcast to session channel
      broadcast_attachment(session, attachment)

      ServiceResponse.success(
        data: {
          output: "Generated image: #{filename} (#{format_size(image_data.bytesize)})\nSaved to: #{filepath}\nPrompt: #{prompt.truncate(100)}",
          exit_code: 0,
          path: filepath,
          attachment_id: attachment.id
        }
      )
    rescue StandardError => e
      ServiceResponse.failure(error: "Image generation failed: #{e.message}")
    end

    private

    def generate_image(api_key, prompt, size)
      uri = URI("https://api.openai.com/v1/images/generations")

      body = {
        model: "dall-e-3",
        prompt: prompt,
        size: size,
        n: 1,
        quality: "standard"
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 120 # Image generation can take longer

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json

      response = http.request(req)
      data = JSON.parse(response.body)

      if data["data"]&.first&.dig("url")
        data.dig("data", 0, "url")
      else
        Rails.logger.error("DALL-E API error: #{data.inspect}")
        nil
      end
    rescue StandardError => e
      Rails.logger.error("DALL-E request failed: #{e.message}")
      nil
    end

    def download_image(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 30

      response = http.request(Net::HTTP::Get.new(uri))
      return nil unless response.is_a?(Net::HTTPSuccess)

      response.body
    rescue StandardError => e
      Rails.logger.error("Image download failed: #{e.message}")
      nil
    end

    def resolve_api_key(provider)
      # Check provider config first
      key = provider.config&.dig("api_key")
      return key if key.present?

      # Check vault
      entry = VaultEntry.find_by(namespace: "providers", key: "openai_api_key")
      entry&.value
    rescue StandardError
      nil
    end

    def resolve_session
      # Try to get session from config (passed by tool executor dispatcher)
      return config[:session] if config[:session]

      # Try to get from agent's most recent session
      return agent.sessions.order(updated_at: :desc).first if agent

      nil
    end

    def broadcast_attachment(session, attachment)
      blob_url = Rails.application.routes.url_helpers.rails_blob_path(
        attachment.file,
        only_path: true
      )

      attachment_data = {
        id: attachment.id,
        filename: attachment.filename,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        url: blob_url,
        is_image: true
      }

      # Determine if this is team chat or regular agent chat
      if session.team_chat_session.present?
        # Team chat context
        channel = "team_chat_#{session.team_chat_session_id}"
        broadcast_data = {
          type: "file_attachment",
          agent_id: agent.id,
          agent_name: agent.name,
          attachment: attachment_data
        }
      else
        # Regular agent chat
        channel = "session_#{session.id}"
        broadcast_data = {
          type: "file_attachment",
          attachment: attachment_data
        }
      end

      ActionCable.server.broadcast(channel, broadcast_data)
    end

    def format_size(bytes)
      if bytes < 1024
        "#{bytes}B"
      elsif bytes < 1_048_576
        "#{(bytes / 1024.0).round(1)}KB"
      else
        "#{(bytes / 1_048_576.0).round(1)}MB"
      end
    end
  end
end
