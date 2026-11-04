# frozen_string_literal: true

module Providers
  # The global backup brain. The "default_fallback_chain" Setting holds a JSON
  # array of entries pointing at ProviderConfig records by id, for example
  # `[{"provider_config_id": 1}, {"provider_config_id": 2, "model": "qwen3"}]`
  # (Claude first, then the local OpenAI-compatible brain). An entry without a
  # model uses the first model its ProviderConfig defines.
  module DefaultFallback
    SETTING_KEY = "default_fallback_chain"

    # First usable entry after the failed brain: enabled, and not the config
    # (or adapter family) that just failed.
    #
    # @param failed [ProviderConfig, nil] the config whose call failed
    # @param failed_adapter_type [String, nil] adapter type of the failed call
    # @return [Sessions::BrainResolver::Brain, nil] nil when nothing is configured
    def self.call(failed: nil, failed_adapter_type: nil)
      entries.each do |entry|
        config = ProviderConfig.enabled_providers.find_by(id: entry["provider_config_id"])
        next unless config
        next if failed && config.id == failed.id
        next if failed_adapter_type && config.adapter_type == failed_adapter_type

        model = entry["model"].presence || config.model_definitions.first&.dig("name")
        next if model.blank?

        return Sessions::BrainResolver::Brain.new(provider_config: config, provider_name: config.adapter_type, model:)
      end
      nil
    end

    def self.entries
      parsed = JSON.parse(Setting.get(SETTING_KEY).presence || "[]")
      parsed.is_a?(Array) ? parsed.grep(Hash) : []
    rescue JSON::ParserError
      []
    end
  end
end
