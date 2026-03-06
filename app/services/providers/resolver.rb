# frozen_string_literal: true

module Providers
  class Resolver
    ADAPTERS = {
      "openai" => Providers::OpenaiAdapter,
      "anthropic" => Providers::AnthropicAdapter,
      "ollama" => Providers::OllamaAdapter,
      "llama_cpp" => Providers::LlamaCppAdapter
    }.freeze

    def self.call(provider_name:, agent: nil)
      new(provider_name:, agent:).call
    end

    def initialize(provider_name:, agent: nil)
      @provider_name = provider_name
      @agent = agent
    end

    def call
      config = ProviderConfig.enabled_providers.find_by(adapter_type: @provider_name) ||
               ProviderConfig.enabled_providers.find_by(name: @provider_name)

      unless config
        return ServiceResponse.failure(error: "Provider not found: #{@provider_name}")
      end

      adapter_class = ADAPTERS[config.adapter_type]

      unless adapter_class
        return ServiceResponse.failure(error: "Unknown adapter: #{config.adapter_type}")
      end

      api_key = config.api_key(agent: @agent)

      adapter = adapter_class.new(config:, api_key:)
      ServiceResponse.success(data: { adapter: })
    end
  end
end
