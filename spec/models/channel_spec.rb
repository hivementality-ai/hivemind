# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:channel_type) }
    it { should validate_presence_of(:name) }
  end

  describe 'scopes' do
    let!(:enabled_channel) { create(:channel, :telegram, enabled: true) }
    let!(:disabled_channel) { create(:channel, :discord, enabled: false) }

    describe '.enabled_channels' do
      it 'returns only enabled channels' do
        expect(Channel.enabled_channels).to include(enabled_channel)
        expect(Channel.enabled_channels).not_to include(disabled_channel)
      end
    end
  end

  describe 'default values' do
    let(:channel) { Channel.new(name: "Test", channel_type: "telegram") }

    it 'initializes config as empty hash' do
      expect(channel.config).to eq({})
    end

    it 'initializes enabled to true' do
      expect(channel.enabled).to be true
    end
  end

  describe 'factory' do
    it 'creates a valid channel' do
      expect(build(:channel)).to be_valid
    end

    it 'creates valid channels with traits' do
      expect(build(:channel, :telegram)).to be_valid
      expect(build(:channel, :discord)).to be_valid
      expect(build(:channel, :slack)).to be_valid
      expect(build(:channel, :disabled)).to be_valid
    end
  end
end
