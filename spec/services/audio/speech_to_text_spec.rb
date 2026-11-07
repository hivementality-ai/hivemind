# frozen_string_literal: true

require "rails_helper"

RSpec.describe Audio::SpeechToText do
  it "returns nil when no OpenAI-style provider exists" do
    create(:provider_config, :anthropic)
    create(:provider_config, :ollama)

    expect(described_class.adapter).to be_nil
  end

  it "ignores disabled providers" do
    create(:provider_config, :openai, :disabled)

    expect(described_class.adapter).to be_nil
  end

  it "uses an OpenAI provider at the OpenAI address" do
    create(:provider_config, :openai, vault_key: nil)

    expect(described_class.provider_config.adapter_type).to eq("openai")
    expect(described_class.adapter.instance_variable_get(:@base_url)).to eq("https://api.openai.com")
  end

  it "uses an OpenAI-compatible server with a base url, such as local whisper" do
    create(:provider_config, :openai_compatible, base_url: "http://whisper.local:9000/v1")

    adapter = described_class.adapter

    expect(adapter.instance_variable_get(:@base_url)).to eq("http://whisper.local:9000")
  end

  it "skips an OpenAI-compatible provider that has no base url" do
    create(:provider_config, :openai_compatible, base_url: nil)

    expect(described_class.adapter).to be_nil
  end

  it "lets the transcription_provider setting pick one by name and the model setting choose the model" do
    create(:provider_config, :openai, vault_key: nil)
    create(:provider_config, :openai_compatible, name: "Local whisper", base_url: "http://w:1", vault_key: nil)
    Setting.set("transcription_provider", "Local whisper")
    Setting.set("transcription_model", "small")

    adapter = described_class.adapter

    expect(adapter.instance_variable_get(:@base_url)).to eq("http://w:1")
    expect(adapter.instance_variable_get(:@model)).to eq("small")
  end
end
