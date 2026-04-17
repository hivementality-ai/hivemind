# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::ToolLoopConfigSerializer do
  def call(agent)
    described_class.call(agent: agent)
  end

  describe "blank / empty config" do
    it "returns nil when tool_loop_config is empty" do
      agent = create(:agent, name: "Mando", role: "Engineer", tool_loop_config: {})
      expect(call(agent)).to be_nil
    end

    it "returns nil when tool_loop_config is nil" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      agent.update_column(:tool_loop_config, nil)
      expect(call(agent)).to be_nil
    end
  end

  describe "default config" do
    it "returns nil when config exactly matches the default" do
      agent = create(:agent, name: "Mando", role: "Engineer",
        tool_loop_config: Agent::DEFAULT_LOOP_CONFIG)
      expect(call(agent)).to be_nil
    end
  end

  describe "custom config" do
    it "returns the config hash when it differs from the default" do
      custom = { "history_size" => 50 }
      agent  = create(:agent, name: "Mando", role: "Engineer", tool_loop_config: custom)
      expect(call(agent)).to eq(custom)
    end

    it "returns the full config hash as stored" do
      custom = {
        "history_size"              => 50,
        "warning_threshold"         => 8,
        "critical_threshold"        => 15,
        "circuit_breaker_threshold" => 75
      }
      agent = create(:agent, name: "Mando", role: "Engineer", tool_loop_config: custom)
      expect(call(agent)).to eq(custom)
    end
  end
end
