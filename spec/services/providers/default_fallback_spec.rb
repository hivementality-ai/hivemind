# frozen_string_literal: true

require "rails_helper"

RSpec.describe Providers::DefaultFallback do
  let(:claude) { create(:provider_config, adapter_type: "anthropic", model_definitions: [ { "name" => "claude-x" } ]) }
  let(:local) { create(:provider_config, adapter_type: "openai_compatible", model_definitions: [ { "name" => "qwen" } ]) }

  def configure(*entries) = Setting.set(described_class::SETTING_KEY, entries.to_json)

  it "is nil when nothing is configured" do
    expect(described_class.call).to be_nil
  end

  it "is nil when the setting is not valid JSON" do
    Setting.set(described_class::SETTING_KEY, "{oops")
    expect(described_class.call).to be_nil
  end

  it "picks the first entry that is not the failed brain, using its first model" do
    configure({ provider_config_id: claude.id }, { provider_config_id: local.id })

    brain = described_class.call(failed: claude, failed_adapter_type: "anthropic")

    expect(brain.provider_config).to eq(local)
    expect(brain.provider_name).to eq("openai_compatible")
    expect(brain.model).to eq("qwen")
  end

  it "honors an explicit model on the entry" do
    configure({ provider_config_id: local.id, model: "qwen-big" })
    expect(described_class.call.model).to eq("qwen-big")
  end

  it "skips disabled and missing configs" do
    local.update!(enabled: false)
    configure({ provider_config_id: 0 }, { provider_config_id: local.id })
    expect(described_class.call).to be_nil
  end
end
