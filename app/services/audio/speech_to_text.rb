# frozen_string_literal: true

module Audio
  # Finds the speech-to-text service this install already has configured.
  # Any enabled OpenAI or OpenAI-compatible provider (including a local whisper
  # server) works; the Setting "transcription_provider" picks one by name.
  module SpeechToText
    NOT_SET_UP = "No speech-to-text is set up yet. Add an OpenAI or Whisper-compatible " \
                 "provider in Providers settings and try again."
    DEFAULT_MODEL = "whisper-1"

    # @return [OpenaiTranscriber, nil] nil when nothing suitable is configured
    def self.adapter
      config = provider_config
      return unless config

      OpenaiTranscriber.new(
        base_url: config.base_url.presence || OpenaiTranscriber::OPENAI_URL,
        api_key: config.api_key,
        model: Setting.get("transcription_model").presence || DEFAULT_MODEL
      )
    end

    # @return [ProviderConfig, nil]
    def self.provider_config
      scope = ProviderConfig.enabled_providers.where(adapter_type: %w[openai openai_compatible])
      named = Setting.get("transcription_provider").presence
      return scope.find_by(name: named) if named

      scope.find_by(adapter_type: "openai") ||
        scope.where.not(base_url: [ nil, "" ]).order(:id).first
    end
  end
end
