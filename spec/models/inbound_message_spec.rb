# frozen_string_literal: true

require "rails_helper"

RSpec.describe InboundMessage, type: :model do
  describe "associations" do
    it { should belong_to(:channel) }
  end

  describe "validations" do
    subject { build(:inbound_message) }

    it { should validate_presence_of(:external_id) }
    it { should validate_uniqueness_of(:external_id).scoped_to(:channel_id) }
    it { should validate_presence_of(:sender) }
    it { should validate_presence_of(:received_at) }
  end

  describe "scopes" do
    let(:channel) { create(:channel) }
    let!(:msg1) { create(:inbound_message, channel: channel, received_at: 1.hour.ago) }
    let!(:msg2) { create(:inbound_message, channel: channel, received_at: Time.current) }

    it ".recent orders by received_at desc" do
      expect(InboundMessage.recent.first).to eq(msg2)
    end

    it ".for_channel filters by channel" do
      other_channel = create(:channel, name: "other")
      create(:inbound_message, channel: other_channel)
      expect(InboundMessage.for_channel(channel).count).to eq(2)
    end
  end
end
