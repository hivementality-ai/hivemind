# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::HeartbeatConfigDeployer do
  HEARTBEAT_SETTING = described_class::HEARTBEAT_SETTING_KEY
  TASKS_SETTING     = described_class::TASKS_SETTING_KEY

  def build_document(heartbeat_config: nil)
    Swarms::SwarmDocument.new(
      swarm_version:    "1.0",
      name:             "Test Swarm",
      heartbeat_config: heartbeat_config
    )
  end

  after do
    Setting.find_by(key: HEARTBEAT_SETTING)&.destroy
    Setting.find_by(key: TASKS_SETTING)&.destroy
  end

  # ---------------------------------------------------------------------------
  # Skipped when absent
  # ---------------------------------------------------------------------------

  describe "when document has no heartbeat_config" do
    it "returns success" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns action :skipped" do
      result = described_class.call(document: build_document)
      expect(result.payload[:heartbeat_config].action).to eq(:skipped)
    end

    it "does not create any Setting records" do
      expect { described_class.call(document: build_document) }
        .not_to change { Setting.where(key: [HEARTBEAT_SETTING, TASKS_SETTING]).count }
    end
  end

  # ---------------------------------------------------------------------------
  # Applied when present
  # ---------------------------------------------------------------------------

  describe "when document has heartbeat_config" do
    let(:config) do
      {
        "enabled"          => true,
        "interval_minutes" => 15,
        "model"            => "claude-3-5-haiku",
        "provider"         => "anthropic",
        "prompt"           => "Check the board."
      }
    end

    it "returns success" do
      result = described_class.call(document: build_document(heartbeat_config: config))
      expect(result).to be_success
    end

    it "returns action :applied" do
      result = described_class.call(document: build_document(heartbeat_config: config))
      expect(result.payload[:heartbeat_config].action).to eq(:applied)
    end

    it "writes the heartbeat Setting" do
      described_class.call(document: build_document(heartbeat_config: config))
      raw     = Setting.get(HEARTBEAT_SETTING)
      stored  = JSON.parse(raw)

      expect(stored["enabled"]).to eq(true)
      expect(stored["interval_minutes"]).to eq(15)
      expect(stored["model"]).to eq("claude-3-5-haiku")
      expect(stored["provider"]).to eq("anthropic")
      expect(stored["prompt"]).to eq("Check the board.")
    end

    it "overwrites an existing heartbeat setting" do
      Setting.set(HEARTBEAT_SETTING, { "enabled" => false, "model" => "gpt-3.5" }.to_json)
      described_class.call(document: build_document(heartbeat_config: config))
      stored = JSON.parse(Setting.get(HEARTBEAT_SETTING))
      expect(stored["model"]).to eq("claude-3-5-haiku")
    end
  end

  # ---------------------------------------------------------------------------
  # Checklist
  # ---------------------------------------------------------------------------

  describe "with checklist items" do
    let(:config_with_checklist) do
      {
        "enabled"   => true,
        "checklist" => [
          { "task" => "Review PRs" },
          { "task" => "Check CI" }
        ]
      }
    end

    it "writes standing tasks to heartbeat_tasks Setting" do
      described_class.call(document: build_document(heartbeat_config: config_with_checklist))
      raw   = Setting.get(TASKS_SETTING)
      items = JSON.parse(raw)

      expect(items.size).to eq(2)
      expect(items.map { |i| i["task"] }).to match_array(["Review PRs", "Check CI"])
    end

    it "marks all written tasks as protected" do
      described_class.call(document: build_document(heartbeat_config: config_with_checklist))
      items = JSON.parse(Setting.get(TASKS_SETTING))
      expect(items.all? { |i| i["protected"] == true }).to be true
    end

    it "skips blank task entries" do
      config = { "enabled" => true, "checklist" => [{ "task" => "" }, { "task" => "Valid Task" }] }
      described_class.call(document: build_document(heartbeat_config: config))
      items = JSON.parse(Setting.get(TASKS_SETTING))
      expect(items.size).to eq(1)
      expect(items.first["task"]).to eq("Valid Task")
    end
  end

  describe "when checklist is absent" do
    it "does not write the heartbeat_tasks setting" do
      config = { "enabled" => true }
      described_class.call(document: build_document(heartbeat_config: config))
      expect(Setting.find_by(key: TASKS_SETTING)).to be_nil
    end
  end
end
