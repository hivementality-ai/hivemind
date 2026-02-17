# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentChannel, type: :model do
  let(:agent) { create(:agent) }
  let(:channel) { create(:channel, channel_type: "slack") }

  describe "validations" do
    subject { build(:agent_channel, agent: agent, channel: channel) }

    it { is_expected.to validate_presence_of(:agent_id) }
    it { is_expected.to validate_presence_of(:channel_id) }
    it { is_expected.to validate_uniqueness_of(:agent_id).scoped_to(:channel_id) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:agent) }
    it { is_expected.to belong_to(:channel) }
  end

  describe "scopes" do
    let!(:default_agent_channel) { create(:agent_channel, agent: agent, channel: channel, is_default: true) }
    let!(:regular_agent_channel) { create(:agent_channel, channel: channel, is_default: false) }

    describe ".default_for_channel" do
      it "returns only default agent channels for the given channel" do
        result = described_class.default_for_channel(channel)
        expect(result).to contain_exactly(default_agent_channel)
      end
    end

    describe ".with_bot_token" do
      let!(:agent_channel_with_token) {
        create(:agent_channel).tap do |ac|
          ac.update_column(:vault_token_key, "test_key") # Skip callback
        end
      }
      let!(:agent_channel_without_token) {
        create(:agent_channel).tap do |ac|
          ac.update_column(:vault_token_key, nil) # Skip callback
        end
      }

      it "returns only agent channels with vault_token_key" do
        result = described_class.with_bot_token
        expect(result).to include(agent_channel_with_token)
        expect(result).not_to include(agent_channel_without_token)
      end
    end
  end

  describe "#bot_token" do
    let(:agent_channel) { create(:agent_channel, vault_token_key: "test_key") }
    let(:vault_entry) { double(value: "xoxb-test-token") }

    context "when vault_token_key is present and entry exists" do
      before do
        allow(VaultEntry).to receive(:find_by)
          .with(namespace: "channel_credentials", key: "test_key")
          .and_return(vault_entry)
      end

      it "returns the token from vault" do
        expect(agent_channel.bot_token).to eq("xoxb-test-token")
      end
    end

    context "when vault_token_key is blank" do
      let(:agent_channel) { create(:agent_channel, vault_token_key: nil) }

      it "returns nil" do
        expect(agent_channel.bot_token).to be_nil
      end
    end
  end

  describe "#has_bot_token?" do
    context "when vault_token_key is present and token exists" do
      let(:agent_channel) { create(:agent_channel, vault_token_key: "test_key") }

      before do
        allow(VaultEntry).to receive(:find_by)
          .with(namespace: "channel_credentials", key: "test_key")
          .and_return(double(value: "xoxb-test-token"))
      end

      it "returns true" do
        expect(agent_channel.has_bot_token?).to be true
      end
    end

    context "when vault_token_key is blank" do
      let(:agent_channel) { create(:agent_channel, vault_token_key: nil) }

      it "returns false" do
        expect(agent_channel.has_bot_token?).to be false
      end
    end
  end

  describe "callbacks" do
    describe "ensuring single default per channel" do
      let!(:existing_default) { create(:agent_channel, channel: channel, is_default: true) }

      it "removes default from other agent channels when setting new default" do
        new_agent_channel = create(:agent_channel, channel: channel, is_default: true)

        expect(existing_default.reload.is_default?).to be false
        expect(new_agent_channel.is_default?).to be true
      end
    end

    describe "setting vault_token_key" do
      let(:agent_channel) { build(:agent_channel, agent: agent, channel: channel, vault_token_key: nil) }

      it "sets vault_token_key based on agent_id" do
        agent_channel.save!
        expect(agent_channel.vault_token_key).to eq("slack_agent_#{agent.id}_bot_token")
      end
    end
  end
end
