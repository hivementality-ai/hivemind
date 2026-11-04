# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackgroundModel do
  let(:anthropic_agent) { build(:agent, model_provider: "anthropic", llm_model: "claude-opus-4-7") }
  let(:local_agent)     { build(:agent, model_provider: "ollama", llm_model: "llama3.2:3b") }

  around do |example|
    original = ENV.delete(described_class::ENV_KEY)
    example.run
  ensure
    original ? ENV[described_class::ENV_KEY] = original : ENV.delete(described_class::ENV_KEY)
  end

  it "uses the small Claude model for an Anthropic agent" do
    expect(described_class.for(anthropic_agent)).to eq(LlmModelRegistry::Anthropic::DEFAULT_SUMMARIZER)
  end

  it "uses the small GPT model for an OpenAI agent" do
    agent = build(:agent, model_provider: "openai", llm_model: "gpt-5.4")

    expect(described_class.for(agent)).to eq(LlmModelRegistry::OpenAI::DEFAULT_SUMMARIZER)
  end

  it "keeps a local agent's own model" do
    expect(described_class.for(local_agent)).to eq("llama3.2:3b")
  end

  it "lets the env var override the default" do
    ENV[described_class::ENV_KEY] = "my-small-model"

    expect(described_class.for(anthropic_agent)).to eq("my-small-model")
    expect(described_class.for(local_agent)).to eq("my-small-model")
  end

  it "lets the setting override the default" do
    Setting.set(described_class::SETTING_KEY, "setting-model")

    expect(described_class.for(anthropic_agent)).to eq("setting-model")
  end
end
