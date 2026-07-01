# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::Registry do
  describe '.adapter_for' do
    let(:channel) { double('channel', channel_type: channel_type) }

    context 'with supported channel types' do
      it 'returns Discord adapter for discord channel' do
        channel = double('channel', channel_type: 'discord')

        expect(Channels::DiscordAdapter).to receive(:new).with(channel).and_return(double)
        result = described_class.adapter_for(channel)

        expect(result).to be_present
      end

      it 'returns Slack adapter for slack channel' do
        channel = double('channel', channel_type: 'slack')

        expect(Channels::SlackAdapter).to receive(:new).with(channel).and_return(double)
        result = described_class.adapter_for(channel)

        expect(result).to be_present
      end

      it 'returns Telegram adapter for telegram channel' do
        channel = double('channel', channel_type: 'telegram')

        expect(Channels::TelegramAdapter).to receive(:new).with(channel).and_return(double)
        result = described_class.adapter_for(channel)

        expect(result).to be_present
      end

      it 'returns WhatsApp adapter for whatsapp channel' do
        channel = double('channel', channel_type: 'whatsapp')

        expect(Channels::WhatsappAdapter).to receive(:new).with(channel).and_return(double)
        result = described_class.adapter_for(channel)

        expect(result).to be_present
      end

      it 'returns Signal adapter for signal channel' do
        channel = double('channel', channel_type: 'signal')

        expect(Channels::SignalAdapter).to receive(:new).with(channel).and_return(double)
        result = described_class.adapter_for(channel)

        expect(result).to be_present
      end
    end

    context 'with unsupported channel type' do
      it 'raises error for unknown channel type' do
        channel = double('channel', channel_type: 'unsupported')

        expect {
          described_class.adapter_for(channel)
        }.to raise_error("Unknown channel type: unsupported")
      end

      it 'raises error for nil channel type' do
        channel = double('channel', channel_type: nil)

        expect {
          described_class.adapter_for(channel)
        }.to raise_error("Unknown channel type: ")
      end

      it 'raises error for empty string channel type' do
        channel = double('channel', channel_type: '')

        expect {
          described_class.adapter_for(channel)
        }.to raise_error("Unknown channel type: ")
      end
    end

    context 'when adapter class does not exist' do
      before do
        # Temporarily modify the BUILTIN_ADAPTERS constant
        stub_const("Channels::Registry::BUILTIN_ADAPTERS", {
          "nonexistent" => "Channels::NonexistentAdapter"
        })
      end

      it 'raises NameError when adapter class cannot be found' do
        channel = double('channel', channel_type: 'nonexistent')

        expect {
          described_class.adapter_for(channel)
        }.to raise_error(NameError)
      end
    end
  end

  describe '.supported_types' do
    it 'returns all supported channel types' do
      types = described_class.supported_types

      expect(types).to be_an(Array)
      expect(types).to include('discord', 'slack', 'telegram', 'whatsapp', 'signal', 'matrix', 'email', 'mattermost', 'line', 'feishu')
      expect(types.size).to eq(Channels::Registry::BUILTIN_ADAPTERS.size)
    end

    it 'returns keys from ADAPTERS constant' do
      expected_types = Channels::Registry::ADAPTERS.keys
      actual_types = described_class.supported_types

      expect(actual_types).to eq(expected_types)
    end

    it 'returns consistent results on multiple calls' do
      types1 = described_class.supported_types
      types2 = described_class.supported_types

      expect(types1).to eq(types2)
    end
  end

  describe 'ADAPTERS constant' do
    it 'is frozen' do
      expect(Channels::Registry::ADAPTERS).to be_frozen
    end

    it 'contains string keys and values' do
      Channels::Registry::ADAPTERS.each do |key, value|
        expect(key).to be_a(String)
        expect(value).to be_a(String)
        expect(value).to start_with('Channels::')
        expect(value).to end_with('Adapter')
      end
    end

    it 'has the expected structure' do
      expect(Channels::Registry::ADAPTERS).to eq(Channels::Registry::BUILTIN_ADAPTERS)
      expect(Channels::Registry::ADAPTERS).to include("feishu" => "Channels::FeishuAdapter")
    end
  end

  describe 'integration with actual adapter classes' do
    # These tests verify that the referenced classes exist
    # Skip if running in isolation without the actual adapter classes

    it 'references existing adapter classes' do
      Channels::Registry::ADAPTERS.each do |channel_type, class_name|
        expect { class_name.constantize }.not_to raise_error,
          "Adapter class #{class_name} for #{channel_type} should exist"
      end
    end

    it 'adapter classes can be instantiated with a channel' do
      channel = double('channel')

      Channels::Registry::ADAPTERS.each do |channel_type, class_name|
        adapter_class = class_name.constantize
        expect { adapter_class.new(channel) }.not_to raise_error,
          "#{class_name} should accept a channel in its constructor"
      end
    end
  end

  describe 'case sensitivity' do
    it 'is case sensitive for channel types' do
      channel_upper = double('channel', channel_type: 'DISCORD')
      channel_mixed = double('channel', channel_type: 'Discord')

      expect {
        described_class.adapter_for(channel_upper)
      }.to raise_error("Unknown channel type: DISCORD")

      expect {
        described_class.adapter_for(channel_mixed)
      }.to raise_error("Unknown channel type: Discord")
    end
  end
end
