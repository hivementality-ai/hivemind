# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutboundMessage, type: :model do
  describe "associations" do
    it { should belong_to(:channel) }
  end

  describe "validations" do
    it { should validate_presence_of(:recipient) }
    it { should validate_presence_of(:sent_at) }
  end

  describe "scopes" do
    let(:channel) { create(:channel) }
    let!(:msg1) { create(:outbound_message, channel: channel, sent_at: 1.hour.ago) }
    let!(:msg2) { create(:outbound_message, channel: channel, sent_at: Time.current) }

    it ".recent orders by sent_at desc" do
      expect(OutboundMessage.recent.first).to eq(msg2)
    end

    it ".for_channel filters by channel" do
      other_channel = create(:channel, name: "other")
      create(:outbound_message, channel: other_channel)
      expect(OutboundMessage.for_channel(channel).count).to eq(2)
    end
  end
end
