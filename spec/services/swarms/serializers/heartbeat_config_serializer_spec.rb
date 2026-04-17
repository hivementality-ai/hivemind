# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::HeartbeatConfigSerializer do
  HEARTBEAT_KEY = described_class::HEARTBEAT_SETTING_KEY
  TASKS_KEY     = described_class::TASKS_SETTING_KEY

  after do
    Setting.find_by(key: HEARTBEAT_KEY)&.destroy
    Setting.find_by(key: TASKS_KEY)&.destroy
  end

  # ---------------------------------------------------------------------------
  # No config stored
  # ---------------------------------------------------------------------------

  describe "when no heartbeat setting exists" do
    it "returns nil" do
      expect(described_class.call).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Basic config
  # ---------------------------------------------------------------------------

  describe "with a full heartbeat config" do
    before do
      Setting.set(HEARTBEAT_KEY, {
        "enabled"          => true,
        "interval_minutes" => 30,
        "model"            => "claude-3-5-haiku",
        "provider"         => "anthropic",
        "prompt"           => "Check the task board.",
        "light_context"    => false
      }.to_json)
    end

    it "includes enabled" do
      expect(described_class.call["enabled"]).to eq(true)
    end

    it "includes interval_minutes" do
      expect(described_class.call["interval_minutes"]).to eq(30)
    end

    it "includes model" do
      expect(described_class.call["model"]).to eq("claude-3-5-haiku")
    end

    it "includes provider" do
      expect(described_class.call["provider"]).to eq("anthropic")
    end

    it "includes prompt" do
      expect(described_class.call["prompt"]).to eq("Check the task board.")
    end

    it "omits light_context when false" do
      expect(described_class.call).not_to have_key("light_context")
    end
  end

  describe "when light_context is true" do
    before do
      Setting.set(HEARTBEAT_KEY, { "enabled" => true, "light_context" => true }.to_json)
    end

    it "includes light_context: true" do
      expect(described_class.call["light_context"]).to eq(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Checklist
  # ---------------------------------------------------------------------------

  describe "with heartbeat standing tasks" do
    before do
      Setting.set(HEARTBEAT_KEY, { "enabled" => true }.to_json)
      Setting.set(TASKS_KEY, [
        { "task" => "Check CI status", "protected" => true, "added_by" => "user@example.com" },
        { "task" => "One-off task",    "protected" => false }
      ].to_json)
    end

    it "includes only protected checklist items" do
      result = described_class.call
      expect(result["checklist"].size).to eq(1)
      expect(result["checklist"].first["task"]).to eq("Check CI status")
    end

    it "omits the added_by metadata from checklist items" do
      result = described_class.call
      expect(result["checklist"].first).not_to have_key("added_by")
    end
  end

  describe "with no standing tasks" do
    before do
      Setting.set(HEARTBEAT_KEY, { "enabled" => true }.to_json)
    end

    it "omits the checklist key" do
      expect(described_class.call).not_to have_key("checklist")
    end
  end

  # ---------------------------------------------------------------------------
  # Schema compatibility
  # ---------------------------------------------------------------------------

  describe "schema compatibility" do
    before do
      Setting.set(HEARTBEAT_KEY, {
        "enabled"          => true,
        "interval_minutes" => 15,
        "model"            => "gpt-4",
        "provider"         => "openai",
        "prompt"           => "Do things."
      }.to_json)
      Setting.set(TASKS_KEY, [
        { "task" => "Check tasks", "protected" => true }
      ].to_json)
    end

    it "produces output valid against SwarmSchema heartbeat_config section" do
      result = described_class.call
      raw    = { "swarm_version" => "1.0", "name" => "Test", "heartbeat_config" => result }
      validation = Swarms::SwarmSchema.validate(raw)
      expect(validation).to be_valid, validation.errors.inspect
    end
  end
end
