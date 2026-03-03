# frozen_string_literal: true

module OpenClaw
  class ChannelParser
    CREDENTIAL_PATTERN = /token|key|secret|password|credential/i
    CHANNEL_TYPE_MAP = {
      "slack" => "slack",
      "discord" => "discord",
      "telegram" => "telegram",
      "whatsapp" => "whatsapp"
    }.freeze

    def self.call(workspace_path:, agent:)
      new(workspace_path:, agent:).call
    end

    def initialize(workspace_path:, agent:)
      @workspace_path = workspace_path
      @agent = agent
    end

    def call
      config_path = File.join(@workspace_path, "config.json")
      return ServiceResponse.success(data: { created: [], skipped: [], details: [] }) unless File.exist?(config_path)

      config = JSON.parse(File.read(config_path))
      channels_data = config["channels"] || []
      return ServiceResponse.success(data: { created: [], skipped: [], details: [] }) if channels_data.empty?

      created = []
      skipped = []

      channels_data.each do |ch|
        type = CHANNEL_TYPE_MAP[ch["type"]&.downcase]
        name = ch["name"] || "#{type || ch['type']} channel"

        unless type
          skipped << { name: name, reason: "Unsupported channel type: #{ch['type']}" }
          next
        end

        # Check for existing channel with same name and type
        existing = Channel.find_by(name: name, channel_type: type)
        if existing && AgentChannel.exists?(agent: @agent, channel: existing)
          skipped << { name: name, reason: "Already exists" }
          next
        end

        sanitized_config = sanitize_config(ch.fetch("config", {}))

        channel = existing || Channel.create!(
          name: name,
          channel_type: type,
          config: sanitized_config,
          enabled: false
        )

        # Force disabled on import
        channel.update!(enabled: false) if channel.enabled?

        # Create join without vault_token_key (user re-auths later)
        AgentChannel.find_or_create_by!(agent: @agent, channel: channel)

        created << { name: name, type: type }
      end

      ServiceResponse.success(data: { created: created, skipped: skipped, details: channels_data.map { |c| c["name"] || c["type"] } })
    rescue StandardError => e
      ServiceResponse.failure(error: "Channel import failed: #{e.message}")
    end

    private

    def sanitize_config(config)
      return {} unless config.is_a?(Hash)

      config.each_with_object({}) do |(key, value), sanitized|
        next if key.match?(CREDENTIAL_PATTERN)

        sanitized[key] = if value.is_a?(Hash)
          sanitize_config(value)
        else
          value
        end
      end
    end
  end
end
