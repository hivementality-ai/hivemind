# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::DiscordAdapter do
  let(:channel) { create(:channel, channel_type: 'discord') }
  let(:adapter) { described_class.new(channel) }

  describe '#receive' do
    let(:discord_message) do
      {
        id: "12345678901234567890",
        content: "Hello, bot!",
        channel_id: "987654321098765432",
        guild_id: "111111111111111111",
        author: {
          id: "222222222222222222",
          username: "testuser",
          discriminator: "1234"
        }
      }
    end

    context 'with valid Discord message' do
      it 'processes the message and logs inbound message' do
        expect {
          result = adapter.receive(discord_message)
          
          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true
          expect(result.data[:inbound_message]).to be_a(InboundMessage)
        }.to change(InboundMessage, :count).by(1)

        inbound = InboundMessage.last
        expect(inbound.external_id).to eq("12345678901234567890")
        expect(inbound.sender).to eq("222222222222222222")
        expect(inbound.content).to eq("Hello, bot!")
        expect(inbound.metadata["channel_id"]).to eq("987654321098765432")
        expect(inbound.metadata["guild_id"]).to eq("111111111111111111")
        expect(inbound.metadata["author"]["username"]).to eq("testuser")
      end

      it 'handles string keys in input' do
        string_key_message = {
          "id" => "12345678901234567890",
          "content" => "Hello, bot!",
          "channel_id" => "987654321098765432",
          "author" => {
            "id" => "222222222222222222",
            "username" => "testuser"
          }
        }

        result = adapter.receive(string_key_message)
        
        expect(result.success?).to be true
        expect(InboundMessage.last.content).to eq("Hello, bot!")
      end
    end

    context 'with message without content' do
      let(:empty_message) do
        {
          id: "12345678901234567890",
          type: 1,  # Application command
          channel_id: "987654321098765432"
        }
      end

      it 'skips processing and returns success' do
        result = adapter.receive(empty_message)
        
        expect(result.success?).to be true
        expect(result.data[:skipped]).to be true
      end

      it 'does not create an inbound message' do
        expect {
          adapter.receive(empty_message)
        }.not_to change(InboundMessage, :count)
      end
    end

    context 'when logging fails' do
      before do
        allow_any_instance_of(described_class).to receive(:log_inbound_message).and_raise(StandardError, "Database error")
      end

      it 'returns failure with error message' do
        result = adapter.receive(discord_message)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Discord receive failed: Database error")
      end
    end

    context 'with malformed message data' do
      it 'handles missing author gracefully' do
        malformed_message = {
          id: "12345678901234567890",
          content: "Hello, bot!",
          channel_id: "987654321098765432"
          # Missing author
        }

        result = adapter.receive(malformed_message)
        
        expect(result.success?).to be true
        inbound = InboundMessage.last
        expect(inbound.sender).to eq("") # author.id is nil, converted to string
      end
    end
  end

  describe '#send_message' do
    let(:channel_id) { "987654321098765432" }
    let(:content) { "Hello from bot!" }
    let(:bot_token) { "discord_bot_token_123" }

    before do
      # Mock vault entry for bot token
      allow(VaultEntry).to receive(:find_by).with(
        namespace: "channel_credentials",
        key: "discord_bot_token"
      ).and_return(double(encrypted_value: bot_token))
    end

    context 'with successful Discord API response' do
      let(:discord_response) do
        {
          "id" => "888888888888888888",
          "content" => content,
          "channel_id" => channel_id,
          "timestamp" => "2024-01-01T12:00:00.000Z"
        }
      end

      before do
        allow(Faraday).to receive(:post).and_return(
          double(success?: true, body: discord_response.to_json)
        )
      end

      it 'sends message to Discord API' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:response]).to eq(discord_response)

        expect(Faraday).to have_received(:post).with(
          "https://discord.com/api/v10/channels/#{channel_id}/messages",
          { content: content }.to_json,
          {
            "Authorization" => "Bot #{bot_token}",
            "Content-Type" => "application/json"
          }
        )
      end

      it 'logs outbound message' do
        expect {
          result = adapter.send_message(to: channel_id, content: content)
          
          expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        }.to change(OutboundMessage, :count).by(1)

        outbound = OutboundMessage.last
        expect(outbound.recipient).to eq(channel_id)
        expect(outbound.content).to eq(content)
        expect(outbound.metadata["message_id"]).to eq("888888888888888888")
        expect(outbound.metadata["response"]).to eq(discord_response)
      end

      it 'supports embeds option' do
        embeds = [{ title: "Test Embed", description: "This is a test" }]
        
        adapter.send_message(to: channel_id, content: content, embeds: embeds)
        
        expect(Faraday).to have_received(:post).with(
          anything,
          { content: content, embeds: embeds }.to_json,
          anything
        )
      end

      it 'ignores unsupported options' do
        adapter.send_message(
          to: channel_id, 
          content: content, 
          embeds: [{ title: "Test" }],
          unsupported_option: "ignored"
        )
        
        expect(Faraday).to have_received(:post).with(
          anything,
          { content: content, embeds: [{ title: "Test" }] }.to_json,
          anything
        )
      end
    end

    context 'when bot token is not configured' do
      before do
        allow(VaultEntry).to receive(:find_by).and_return(nil)
      end

      it 'returns failure with error message' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Bot token not configured")
      end

      it 'does not make API call' do
        adapter.send_message(to: channel_id, content: content)
        
        expect(Faraday).not_to receive(:post)
      end

      it 'does not log outbound message' do
        expect {
          adapter.send_message(to: channel_id, content: content)
        }.not_to change(OutboundMessage, :count)
      end
    end

    context 'when Discord API returns error' do
      before do
        allow(Faraday).to receive(:post).and_return(
          double(success?: false, body: '{"message": "Invalid channel"}')
        )
      end

      it 'returns failure with API error' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to eq('Discord API error: {"message": "Invalid channel"}')
      end

      it 'does not log outbound message on API error' do
        expect {
          adapter.send_message(to: channel_id, content: content)
        }.not_to change(OutboundMessage, :count)
      end
    end

    context 'when HTTP request raises exception' do
      before do
        allow(Faraday).to receive(:post).and_raise(Faraday::TimeoutError, "Request timeout")
      end

      it 'returns failure with exception message' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Discord send failed: Request timeout")
      end
    end

    context 'when JSON parsing fails' do
      before do
        allow(Faraday).to receive(:post).and_return(
          double(success?: true, body: "invalid json")
        )
      end

      it 'returns failure with parsing error' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to include("Discord send failed:")
      end
    end
  end

  describe '#verify_webhook' do
    let(:public_key) { "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890" }
    let(:signature) { "valid_signature_hex" }
    let(:timestamp) { "1640995200" }
    let(:body_content) { "webhook body content" }
    let(:request) do
      double('request',
             headers: {
               "X-Signature-Ed25519" => signature,
               "X-Signature-Timestamp" => timestamp
             },
             raw_post: body_content)
    end

    before do
      # Mock vault entry for public key
      allow(VaultEntry).to receive(:find_by).with(
        namespace: "channel_credentials",
        key: "discord_public_key"
      ).and_return(double(encrypted_value: public_key))
    end

    context 'with valid Ed25519 signature' do
      let(:mock_verify_key) { double('verify_key') }

      before do
        allow(Ed25519::VerifyKey).to receive(:new).with([public_key].pack("H*")).and_return(mock_verify_key)
        allow(mock_verify_key).to receive(:verify).with([signature].pack("H*"), timestamp + body_content)
      end

      it 'returns true for valid signature' do
        result = adapter.verify_webhook(request)
        
        expect(result).to be true
        expect(mock_verify_key).to have_received(:verify).with([signature].pack("H*"), timestamp + body_content)
      end
    end

    context 'with invalid Ed25519 signature' do
      let(:mock_verify_key) { double('verify_key') }

      before do
        allow(Ed25519::VerifyKey).to receive(:new).and_return(mock_verify_key)
        allow(mock_verify_key).to receive(:verify).and_raise(Ed25519::VerifyError, "Invalid signature")
      end

      it 'returns false for invalid signature' do
        result = adapter.verify_webhook(request)
        
        expect(result).to be false
      end
    end

    context 'when signature header is missing' do
      let(:request_without_signature) do
        double('request',
               headers: { "X-Signature-Timestamp" => timestamp },
               raw_post: body_content)
      end

      it 'returns false' do
        result = adapter.verify_webhook(request_without_signature)
        
        expect(result).to be false
      end
    end

    context 'when timestamp header is missing' do
      let(:request_without_timestamp) do
        double('request',
               headers: { "X-Signature-Ed25519" => signature },
               raw_post: body_content)
      end

      it 'returns false' do
        result = adapter.verify_webhook(request_without_timestamp)
        
        expect(result).to be false
      end
    end

    context 'when both headers are missing' do
      let(:request_without_headers) do
        double('request',
               headers: {},
               raw_post: body_content)
      end

      it 'returns false' do
        result = adapter.verify_webhook(request_without_headers)
        
        expect(result).to be false
      end
    end

    context 'when public key is not configured' do
      before do
        allow(VaultEntry).to receive(:find_by).with(
          namespace: "channel_credentials",
          key: "discord_public_key"
        ).and_return(nil)
      end

      it 'returns false' do
        result = adapter.verify_webhook(request)
        
        expect(result).to be false
      end
    end

    context 'when Ed25519 verification raises unexpected error' do
      before do
        allow(Ed25519::VerifyKey).to receive(:new).and_raise(StandardError, "Unexpected error")
      end

      it 'allows the exception to bubble up' do
        expect {
          adapter.verify_webhook(request)
        }.to raise_error(StandardError, "Unexpected error")
      end
    end
  end

  describe 'private methods' do
    describe '#get_bot_token' do
      context 'when token exists in vault' do
        let(:token) { "bot_token_123" }

        before do
          allow(VaultEntry).to receive(:find_by).with(
            namespace: "channel_credentials",
            key: "discord_bot_token"
          ).and_return(double(encrypted_value: token))
        end

        it 'retrieves token from vault' do
          result = adapter.send(:get_bot_token)
          expect(result).to eq(token)
        end
      end

      context 'when token does not exist' do
        before do
          allow(VaultEntry).to receive(:find_by).and_return(nil)
        end

        it 'returns nil' do
          result = adapter.send(:get_bot_token)
          expect(result).to be_nil
        end
      end
    end

    describe '#get_public_key' do
      context 'when key exists in vault' do
        let(:key) { "public_key_hex" }

        before do
          allow(VaultEntry).to receive(:find_by).with(
            namespace: "channel_credentials",
            key: "discord_public_key"
          ).and_return(double(encrypted_value: key))
        end

        it 'retrieves key from vault' do
          result = adapter.send(:get_public_key)
          expect(result).to eq(key)
        end
      end

      context 'when key does not exist' do
        before do
          allow(VaultEntry).to receive(:find_by).and_return(nil)
        end

        it 'returns nil' do
          result = adapter.send(:get_public_key)
          expect(result).to be_nil
        end
      end
    end
  end

  describe 'inheritance from BaseAdapter' do
    it 'inherits from BaseAdapter' do
      expect(described_class).to be < Channels::BaseAdapter
    end

    it 'has access to BaseAdapter methods' do
      expect(adapter).to respond_to(:webhook_secret)
      expect(adapter).to respond_to(:log_inbound_message)
      expect(adapter).to respond_to(:log_outbound_message)
    end
  end

  describe 'constants' do
    it 'defines BASE_URL constant' do
      expect(described_class::BASE_URL).to eq("https://discord.com/api/v10")
    end
  end
end