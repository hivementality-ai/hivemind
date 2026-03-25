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
        [
          { id: "claude-opus-4-6", name: "Claude Opus 4.6" },
          { id: "claude-sonnet-4-6", name: "Claude Sonnet 4.6" },
          { id: "claude-sonnet-4-5", name: "Claude Sonnet 4.5" },
          { id: "claude-haiku-4-5", name: "Claude Haiku 4.5" }
        ]
      end

      def fetch_openai_models
        [
          { id: "gpt-5.4", name: "GPT-5.4" },
          { id: "gpt-5.4-mini", name: "GPT-5.4 Mini" },
          { id: "gpt-5.4-nano", name: "GPT-5.4 Nano" },
          { id: "gpt-5.3-codex", name: "GPT-5.3 Codex" },
          { id: "o3-pro", name: "o3-pro" },
          { id: "o3", name: "o3" },
          { id: "o4-mini", name: "o4-mini" },
          { id: "gpt-5.2", name: "GPT-5.2" },
          { id: "gpt-4.1", name: "GPT-4.1" }
        ]
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
