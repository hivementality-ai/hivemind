# frozen_string_literal: true

module Providers
  class Resolver
    ADAPTERS = {
      "openai" => Providers::OpenaiAdapter,
      "anthropic" => Providers::AnthropicAdapter,
      "ollama" => Providers::OllamaAdapter,
      "openai_compatible" => Providers::OpenaiCompatibleAdapter
    }.freeze

    def self.call(provider_name:, agent: nil, failover: true)
      new(provider_name:, agent:, failover:).call
    end

    def initialize(provider_name:, agent: nil, failover: true)
      @provider_name = provider_name
      @agent = agent
      @failover = failover
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
      adapter = wrap_failover(adapter)
      ServiceResponse.success(data: { adapter: })
    end

    private

    # Wrap the adapter in the agent's failover chain (if configured) so every
    # call site — chat jobs, background jobs, ToolLoop — gets failover for
    # free. FailoverAdapter resolves chain entries with failover: false to
    # avoid re-wrapping.
    def wrap_failover(adapter)
      return adapter unless @failover && @agent.respond_to?(:fallback_models)

      chain = @agent.fallback_models
      return adapter if chain.blank?

      FailoverAdapter.new(primary: adapter, chain:, agent: @agent)
    end
  end
end
