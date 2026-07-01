# frozen_string_literal: true

module Api
  module V1
    class ProvidersController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!

      # GET /api/v1/providers/models?provider=ollama
      def models
        provider = params[:provider]

        models = case provider
        when "ollama"
                   fetch_ollama_models
        when "anthropic"
                   fetch_anthropic_models
        when "openai"
                   fetch_openai_models
        when "openai_compatible"
                   fetch_openai_compatible_models
        else
                   []
        end

        render json: { models: models }
      end

      private

      def fetch_ollama_models
        config = ProviderConfig.find_by(adapter_type: "ollama")
        return [] unless config

        # Return manually configured models from model_definitions
        configured = (config.model_definitions || []).map do |m|
          { id: m["id"], name: format_model_name(m["id"]) }
        end
        return configured if configured.any?

        # Fall back to remote detection if no models are configured
        adapter = Providers::OllamaAdapter.new(config: config)
        result = adapter.models
        if result.success?
          result.data[:models].map { |name| { id: name, name: format_model_name(name) } }
        else
          []
        end
      rescue StandardError => e
        Rails.logger.warn("Ollama model fetch failed: #{e.message}")
        []
      end

      def fetch_anthropic_models
        auto_option = [ { id: "auto", name: "Auto (route per task)" } ]
        auto_option + LlmModelRegistry.supported_for_provider("anthropic").map do |m|
          { id: m.api_id, name: m.display_name }
        end
      end

      def fetch_openai_models
        auto_option = [ { id: "auto", name: "Auto (route per task)" } ]
        auto_option + LlmModelRegistry.supported_for_provider("openai").map do |m|
          { id: m.api_id, name: m.display_name }
        end
      end

      def fetch_openai_compatible_models
        config = ProviderConfig.find_by(adapter_type: "openai_compatible")
        return [] unless config

        # Return manually configured models from model_definitions
        configured = (config.model_definitions || []).map do |m|
          { id: m["id"], name: m["id"] }
        end
        return configured if configured.any?

        # Fall back to remote detection if no models are configured
        adapter = Providers::OpenaiCompatibleAdapter.new(config: config)
        result = adapter.models
        if result.success?
          result.data[:models].map { |name| { id: name, name: name } }
        else
          []
        end
      rescue StandardError => e
        Rails.logger.warn("OpenAI Compatible model fetch failed: #{e.message}")
        []
      end

      def format_model_name(name)
        # "llama3.2:3b" → "Llama 3.2 (3B)"
        base, tag = name.split(":")
        display = base.gsub(/([a-z])(\d)/, '\1 \2').gsub(/\./, ".").titleize
        display += " (#{tag.upcase})" if tag
        display
      end
    end
  end
end
