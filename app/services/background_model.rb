# frozen_string_literal: true

# Picks the model for post-turn bookkeeping (memory extraction, summaries,
# titles) so it never runs on the agent's main model.
#
# Anthropic agents get the small Claude model, OpenAI agents the small GPT
# model, and any other provider (local or OpenAI-compatible) keeps its own
# model, which is already cheap. The Setting "background_model" or the
# HIVEMIND_BACKGROUND_MODEL env var overrides all of it.
module BackgroundModel
  ENV_KEY     = "HIVEMIND_BACKGROUND_MODEL"
  SETTING_KEY = "background_model"

  # @param agent [Agent]
  # @return [String] model id to pass as the chat `model` option
  def self.for(agent)
    override || default_for(agent)
  end

  def self.override
    Setting.get(SETTING_KEY).presence || ENV[ENV_KEY].presence
  end

  def self.default_for(agent)
    case agent.model_provider
    when "anthropic" then LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER
    when "openai"    then LlmModelRegistry::OpenAI::DEFAULT_SUMMARIZER
    else agent.llm_model
    end
  end
  private_class_method :default_for
end
