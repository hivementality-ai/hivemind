# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tools::MessageExecutor, type: :service do
  let(:executor) { described_class.new(input: input, config: {}, agent: nil) }

  before do
    # Mock Channels::Registry
    @mock_adapter = instance_double('ChannelAdapter')
    allow(Channels::Registry).to receive(:adapter_for).and_return(@mock_adapter)
  end

  describe '#call' do
    context 'with send action' do
      let(:input) { { "action" => "send", "channel" => "discord", "message" => "Hello, world!" } }

      before do
        @discord_channel = create(:channel, name: 'general', channel_type: 'discord', enabled: true)
        allow(@mock_adapter).to receive(:send_message).and_return(ServiceResponse.success(data: { message_id: '12345' }))
      end

      it 'sends message successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Message sent via discord")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls adapter with correct parameters' do
        executor.call
        expect(Channels::Registry).to have_received(:adapter_for).with(@discord_channel)
        expect(@mock_adapter).to have_received(:send_message).with(to: "", content: "Hello, world!")
      end

      context 'with recipient specified' do
        let(:input) { { "action" => "send", "channel" => "discord", "to" => "user123", "message" => "Hi there!" } }

        it 'includes recipient in output' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("Message sent via discord to user123")
        end

        it 'passes recipient to adapter' do
          executor.call
          expect(@mock_adapter).to have_received(:send_message).with(to: "user123", content: "Hi there!")
        end
      end

      context 'without channel specified' do
        let(:input) { { "action" => "send", "message" => "Default channel message" } }

        before do
          create(:channel, name: 'default', channel_type: 'slack', enabled: true)
        end

        it 'uses first enabled channel' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Message sent")
        end
      end

      context 'with channel found by name instead of type' do
        let(:input) { { "action" => "send", "channel" => "general", "message" => "Test message" } }

        before do
          create(:channel, name: 'general', channel_type: 'discord', enabled: true)
        end

        it 'finds channel by name when type lookup fails' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Message sent")
        end
      end

      context 'without message' do
        let(:input) { { "action" => "send", "channel" => "discord" } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No message provided")
        end
      end

      context 'with empty message' do
        let(:input) { { "action" => "send", "channel" => "discord", "message" => "  " } }

        it 'returns failure' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No message provided")
        end
      end

      context 'when channel not found' do
        let(:input) { { "action" => "send", "channel" => "nonexistent", "message" => "Test" } }

        before do
          create(:channel, name: 'available', channel_type: 'slack', enabled: true)
        end

        it 'returns failure with available channels' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Channel 'nonexistent' not found. Available: slack")
        end
      end

      context 'when no channels configured' do
        let(:input) { { "action" => "send", "channel" => "discord", "message" => "Test" } }

        it 'returns helpful error message' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("No channels configured. Add channels in Platform → Settings.")
        end
      end

      context 'when adapter send fails' do
        let(:input) { { "action" => "send", "channel" => "discord", "message" => "Failed message" } }

        before do
          create(:channel, channel_type: 'discord', enabled: true)
          allow(@mock_adapter).to receive(:send_message).and_return(ServiceResponse.failure(error: "API rate limit exceeded"))
        end

        it 'returns failure with adapter error' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Send failed: API rate limit exceeded")
        end
      end

      context 'when channel is disabled' do
        let(:input) { { "action" => "send", "channel" => "discord", "message" => "Test" } }

        before do
          create(:channel, channel_type: 'discord', enabled: false)
        end

        it 'does not find disabled channels' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to include("Channel 'discord' not found")
        end
      end
    end

    context 'with default send action' do
      let(:input) { { "channel" => "discord", "message" => "Default action message" } }

      before do
        create(:channel, channel_type: 'discord', enabled: true)
        allow(@mock_adapter).to receive(:send_message).and_return(ServiceResponse.success(data: {}))
      end

      it 'defaults to send when no action specified' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to include("Message sent")
      end
    end

    context 'with list_channels action' do
      let(:input) { { "action" => "list_channels" } }

      context 'with channels configured' do
        before do
          create(:channel, name: 'general', channel_type: 'discord', enabled: true)
          create(:channel, name: 'alerts', channel_type: 'slack', enabled: true)
          create(:channel, name: 'disabled', channel_type: 'telegram', enabled: false)
        end

        it 'lists enabled channels' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("Configured channels:")
          expect(result.data[:output]).to include("• general (discord) — ✅ enabled")
          expect(result.data[:output]).to include("• alerts (slack) — ✅ enabled")
          expect(result.data[:output]).not_to include("disabled") # disabled channels are filtered out
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'with no channels configured' do
        it 'shows helpful message' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to eq("No channels configured. Add channels in Platform → Settings.")
          expect(result.data[:exit_code]).to eq(0)
        end
      end

      context 'with mixed enabled/disabled channels' do
        before do
          create(:channel, name: 'enabled', channel_type: 'discord', enabled: true)
          create(:channel, name: 'disabled', channel_type: 'slack', enabled: false)
        end

        it 'only shows enabled channels' do
          result = executor.call
          expect(result).to be_success
          expect(result.data[:output]).to include("enabled (discord)")
          expect(result.data[:output]).not_to include("disabled")
        end
      end
    end

    context 'with react action' do
      let(:input) { { "action" => "react", "channel" => "discord", "message_id" => "123456789", "emoji" => "👍" } }

      before do
        create(:channel, channel_type: 'discord', enabled: true)
        allow(@mock_adapter).to receive(:respond_to?).with(:react).and_return(true)
        allow(@mock_adapter).to receive(:react).and_return(ServiceResponse.success(data: {}))
      end

      it 'reacts to message successfully' do
        result = executor.call
        expect(result).to be_success
        expect(result.data[:output]).to eq("Reacted with 👍")
        expect(result.data[:exit_code]).to eq(0)
      end

      it 'calls adapter react method' do
        executor.call
        expect(@mock_adapter).to have_received(:react).with(message_id: "123456789", emoji: "👍")
      end

      context 'without required fields' do
        context 'without channel' do
          let(:input) { { "action" => "react", "message_id" => "123", "emoji" => "👍" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("channel, message_id, and emoji required")
          end
        end

        context 'without message_id' do
          let(:input) { { "action" => "react", "channel" => "discord", "emoji" => "👍" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("channel, message_id, and emoji required")
          end
        end

        context 'without emoji' do
          let(:input) { { "action" => "react", "channel" => "discord", "message_id" => "123" } }

          it 'returns failure' do
            result = executor.call
            expect(result).to be_failure
            expect(result.error).to eq("channel, message_id, and emoji required")
          end
        end
      end

      context 'when channel does not support reactions' do
        before do
          allow(@mock_adapter).to receive(:respond_to?).with(:react).and_return(false)
        end

        it 'returns failure with unsupported message' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("discord doesn't support reactions")
        end
      end

      context 'when adapter react fails' do
        before do
          allow(@mock_adapter).to receive(:react).and_return(ServiceResponse.failure(error: "Message not found"))
        end

        it 'returns failure with adapter error' do
          result = executor.call
          expect(result).to be_failure
          expect(result.error).to eq("Message not found")
        end
      end
    end

    context 'with unknown action' do
      let(:input) { { "action" => "invalid" } }

      it 'returns failure with supported actions' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Unknown action: invalid")
        expect(result.error).to include("send, list_channels, react")
      end
    end

    context 'when channel lookup raises exception' do
      let(:input) { { "action" => "send", "channel" => "discord", "message" => "Test" } }

      before do
        allow(Channel).to receive_message_chain(:enabled_channels, :find_by).and_raise(StandardError.new("Database error"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Message error: Database error")
      end
    end

    context 'when adapter raises exception' do
      let(:input) { { "action" => "send", "channel" => "discord", "message" => "Test" } }

      before do
        create(:channel, channel_type: 'discord', enabled: true)
        allow(@mock_adapter).to receive(:send_message).and_raise(StandardError.new("Network error"))
      end

      it 'returns failure with error message' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to eq("Message error: Network error")
      end
    end
  end

  describe 'private methods' do
    describe '#find_channel' do
      before do
        @discord_channel = create(:channel, name: 'general', channel_type: 'discord', enabled: true)
        @slack_channel = create(:channel, name: 'alerts', channel_type: 'slack', enabled: true)
        create(:channel, name: 'disabled', channel_type: 'telegram', enabled: false)
      end

      it 'finds channel by channel_type first' do
        channel = executor.send(:find_channel, 'discord')
        expect(channel).to eq(@discord_channel)
      end

      it 'finds channel by name when type lookup fails' do
        channel = executor.send(:find_channel, 'alerts')
        expect(channel).to eq(@slack_channel)
      end

      it 'returns first enabled channel when name is empty' do
        channel = executor.send(:find_channel, '')
        expect(channel).to be_in([@discord_channel, @slack_channel])
      end

      it 'returns nil when channel not found' do
        channel = executor.send(:find_channel, 'nonexistent')
        expect(channel).to be_nil
      end

      it 'does not find disabled channels' do
        channel = executor.send(:find_channel, 'disabled')
        expect(channel).to be_nil
      end
    end

    describe '#not_configured_error' do
      context 'with available channels' do
        before do
          create(:channel, channel_type: 'discord', enabled: true)
          create(:channel, channel_type: 'slack', enabled: true)
        end

        it 'lists available channels' do
          error = executor.send(:not_configured_error, 'telegram')
          expect(error).to eq("Channel 'telegram' not found. Available: discord, slack")
        end
      end

      context 'with no available channels' do
        it 'shows configuration message' do
          error = executor.send(:not_configured_error, 'discord')
          expect(error).to eq("No channels configured. Add channels in Platform → Settings.")
        end
      end
    end
  end

  # Test different channel types and configurations
  describe 'channel integration' do
    context 'with multiple channels of same type' do
      let(:input) { { "action" => "send", "channel" => "discord", "message" => "Test" } }

      before do
        create(:channel, name: 'general', channel_type: 'discord', enabled: true)
        create(:channel, name: 'random', channel_type: 'discord', enabled: true)
        allow(@mock_adapter).to receive(:send_message).and_return(ServiceResponse.success(data: {}))
      end

      it 'finds first matching channel by type' do
        result = executor.call
        expect(result).to be_success
      end
    end

    context 'with case sensitivity' do
      let(:input) { { "action" => "send", "channel" => "Discord", "message" => "Test" } }

      before do
        create(:channel, channel_type: 'discord', enabled: true)
        allow(@mock_adapter).to receive(:send_message).and_return(ServiceResponse.success(data: {}))
      end

      it 'performs case-sensitive lookup' do
        result = executor.call
        expect(result).to be_failure
        expect(result.error).to include("Channel 'Discord' not found")
      end
    end

    context 'with special channel names' do
      let(:input) { { "action" => "send", "channel" => "team-notifications", "message" => "Test" } }

      before do
        create(:channel, name: 'team-notifications', channel_type: 'slack', enabled: true)
        allow(@mock_adapter).to receive(:send_message).and_return(ServiceResponse.success(data: {}))
      end

      it 'handles special characters in channel names' do
        result = executor.call
        expect(result).to be_success
      end
    end
  end
end