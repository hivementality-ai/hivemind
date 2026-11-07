# frozen_string_literal: true

require "rails_helper"

RSpec.describe SimpleMode do
  describe ".enabled?" do
    it "is off by default" do
      expect(described_class.enabled?).to be(false)
    end

    it "round-trips through the setting" do
      described_class.enabled = true
      expect(described_class.enabled?).to be(true)

      described_class.enabled = false
      expect(described_class.enabled?).to be(false)
    end
  end

  describe ".show_nav?" do
    it "shows every entry when off" do
      expect(described_class::HIDDEN_NAV).to all(satisfy { |key| described_class.show_nav?(key) })
    end

    it "hides the listed entries when on" do
      described_class.enabled = true

      expect(described_class::HIDDEN_NAV).to all(satisfy { |key| !described_class.show_nav?(key) })
      expect(described_class.show_nav?(:agents)).to be(true)
    end
  end

  describe ".show_channel_type?" do
    it "keeps iMessage, email and Slack only when on" do
      described_class.enabled = true

      expect(%w[imessage email slack].map { |t| described_class.show_channel_type?(t) }).to all(be(true))
      expect(described_class.show_channel_type?("discord")).to be(false)
    end

    it "allows every type when off" do
      expect(described_class.show_channel_type?("discord")).to be(true)
    end
  end

  describe "tool list offered to the model" do
    let(:agent) { create(:agent) }

    before do
      %w[jira trello coding_agent coding_agent_status shell].each do |type|
        tool = create(:tool, name: "#{type}_tool", executor_type: type)
        create(:agent_tool, agent: agent, tool: tool)
      end
    end

    it "omits the hidden executors when on" do
      described_class.enabled = true

      expect(agent.assigned_tools.map(&:executor_type)).to eq(%w[shell])
    end

    it "offers them again when off" do
      expect(agent.assigned_tools.map(&:executor_type)).to match_array(%w[jira trello coding_agent coding_agent_status shell])
    end
  end
end
