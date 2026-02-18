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
        else
                   []
        end

        render json: { models: models }
      end

      private

      def fetch_ollama_models
        config = ProviderConfig.find_by(adapter_type: "ollama") || ProviderConfig.new(adapter_type: "ollama")
        adapter = Providers::OllamaAdapter.new(config: config)
        result = adapter.models
        if result.success?
          result.data[:models].map { |name| { id: name, name: format_model_name(name) } }
        else
          [ { id: "", name: "Ollama not reachable — is it running?" } ]
        end
      rescue StandardError => e
        Rails.logger.warn("Ollama model fetch failed: #{e.message}")
        [ { id: "", name: "Ollama not reachable — is it running?" } ]
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
        # Try to list models dynamically; fall back to known models
        config = ProviderConfig.find_by(adapter_type: "openai")
        if config&.api_key.present?
          begin
            adapter = Providers::OpenaiAdapter.new(config: config, api_key: config.api_key)
            result = adapter.models
            if result.success?
              return result.data[:models]
                .select { |m| m.match?(/^(gpt-|o[1-4])/) && !m.include?("realtime") && !m.include?("audio") && !m.include?("image") }
                .sort
                .map { |m| { id: m, name: m } }
            end
          rescue StandardError => e
            Rails.logger.warn("Failed to fetch OpenAI models dynamically: #{e.message}")
          end
        end

        # Fallback: known models
        [
          { id: "gpt-4.1", name: "GPT-4.1" },
          { id: "gpt-4.1-mini", name: "GPT-4.1 Mini" },
          { id: "gpt-4.1-nano", name: "GPT-4.1 Nano" },
          { id: "gpt-4o", name: "GPT-4o" },
          { id: "gpt-4o-mini", name: "GPT-4o Mini" },
          { id: "o3", name: "o3" },
          { id: "o3-mini", name: "o3 Mini" },
          { id: "o4-mini", name: "o4-mini" }
        ]
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
