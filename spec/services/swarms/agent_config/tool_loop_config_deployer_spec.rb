# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::AgentConfig::ToolLoopConfigDeployer do
  def call(agent:, config:)
    described_class.call(agent: agent, config: config)
  end

  describe "nil / blank config" do
    it "is a no-op and succeeds" do
      agent = create(:agent, name: "Mando", role: "Engineer")
      result = call(agent: agent, config: nil)
      expect(result).to be_success
      expect(result.payload[:applied]).to be false
    end

    it "leaves existing tool_loop_config unchanged" do
      existing = { "history_size" => 50 }
      agent = create(:agent, name: "Mando", role: "Engineer", tool_loop_config: existing)
      call(agent: agent, config: nil)
      expect(agent.reload.tool_loop_config).to eq(existing)
    end
  end

  describe "valid config" do
    it "applies the config to the agent" do
      agent  = create(:agent, name: "Mando", role: "Engineer")
      config = { "history_size" => 50, "warning_threshold" => 8 }

      result = call(agent: agent, config: config)

      expect(result).to be_success
      expect(result.payload[:applied]).to be true
      expect(agent.reload.tool_loop_config).to eq(config.stringify_keys)
    end

    it "overwrites a pre-existing config" do
      agent  = create(:agent, name: "Mando", role: "Engineer", tool_loop_config: { "history_size" => 10 })
      config = { "history_size" => 100 }

      call(agent: agent, config: config)

      expect(agent.reload.tool_loop_config).to eq({ "history_size" => 100 })
    end
  end

  describe "invalid config" do
    it "returns an error without updating the agent" do
      agent  = create(:agent, name: "Mando", role: "Engineer", tool_loop_config: {})
      result = call(agent: agent, config: { "history_size" => -1 })

      expect(result).to be_error
      expect(result.message).to match(/positive integer/)
      expect(agent.reload.tool_loop_config).to eq({})
    end
  end
end
