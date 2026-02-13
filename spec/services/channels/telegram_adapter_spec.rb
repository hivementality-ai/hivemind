# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::TelegramAdapter do
  let(:channel) { create(:channel, channel_type: 'telegram', config: { "default_chat_id" => "123456789" }) }
  let(:adapter) { described_class.new(channel) }

  describe '#receive' do
    let(:telegram_message) do
      {
        message: {
          message_id: 12345,
          from: {
            id: 987654321,
            username: "testuser",
            first_name: "Test"
          },
          chat: {
            id: -100123456789,
            type: "supergroup",
            title: "Test Group"
          },
          date: 1640995200,
          text: "Hello bot!"
        }
      }
    end

    context 'with valid Telegram message' do
      it 'processes the message and logs inbound message' do
        expect {
          result = adapter.receive(telegram_message)
          
          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true
          expect(result.data[:inbound_message]).to be_a(InboundMessage)
        }.to change(InboundMessage, :count).by(1)

        inbound = InboundMessage.last
        expect(inbound.external_id).to eq("12345")
        expect(inbound.sender).to eq("987654321")
        expect(inbound.content).to eq("Hello bot!")
        expect(inbound.metadata["chat_id"]).to eq(-100123456789)
        expect(inbound.metadata["chat_type"]).to eq("supergroup")
        expect(inbound.metadata["from"]["username"]).to eq("testuser")
        expect(inbound.metadata["date"]).to eq(1640995200)
      end

      it 'handles edited messages' do
        edited_message = {
          edited_message: telegram_message[:message].merge(
            text: "Hello bot! (edited)",
            edit_date: 1640995260
          )
        }

        result = adapter.receive(edited_message)
        
        expect(result.success?).to be true
        inbound = InboundMessage.last
        expect(inbound.content).to eq("Hello bot! (edited)")
      end

      it 'handles string keys in input' do
        string_message = {
          "message" => {
            "message_id" => 12345,
            "from" => {
              "id" => 987654321,
              "username" => "testuser"
            },
            "chat" => {
              "id" => -100123456789,
              "type" => "supergroup"
            },
            "text" => "Hello bot!"
          }
        }

        result = adapter.receive(string_message)
        
        expect(result.success?).to be true
        expect(InboundMessage.last.content).to eq("Hello bot!")
      end

      it 'handles missing text field' do
        message_without_text = {
          message: telegram_message[:message].except(:text)
        }

        result = adapter.receive(message_without_text)
        
        expect(result.success?).to be true
        expect(InboundMessage.last.content).to eq("") # nil.to_s
      end
    end

    context 'with message without content' do
      let(:callback_query) do
        {
          callback_query: {
            id: "callback_123",
            from: { id: 987654321 },
            data: "button_pressed"
          }
        }
      end

      it 'skips processing and returns success' do
        result = adapter.receive(callback_query)
        
        expect(result.success?).to be true
        expect(result.data[:skipped]).to be true
      end

      it 'does not create an inbound message' do
        expect {
          adapter.receive(callback_query)
        }.not_to change(InboundMessage, :count)
      end
    end

    context 'when logging fails' do
      before do
        allow_any_instance_of(described_class).to receive(:log_inbound_message).and_raise(StandardError, "Database error")
      end

      it 'returns failure with error message' do
        result = adapter.receive(telegram_message)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Telegram receive failed: Database error")
      end
    end
  end

  describe '#send_message' do
    let(:chat_id) { "-100123456789" }
    let(:content) { "Hello from bot!" }
    let(:bot_token) { "123456789:ABCdefGHIjklMNOpqrSTUvwxYZ" }

    before do
      # Mock vault entry for bot token
      allow(VaultEntry).to receive(:find_by).with(
        namespace: "channel_credentials",
        key: "telegram_bot_token"
      ).and_return(double(value: bot_token))
    end

    context 'with successful Telegram API response' do
      let(:telegram_response) do
        {
          "ok" => true,
          "result" => {
            "message_id" => 54321,
            "from" => {
              "id" => 123456789,
              "is_bot" => true,
              "first_name" => "Test Bot"
            },
            "chat" => {
              "id" => -100123456789,
              "type" => "supergroup"
            },
            "date" => 1640995200,
            "text" => content
          }
        }
      end

      before do
        allow(adapter).to receive(:post_json).and_return(telegram_response)
      end

      it 'sends message to Telegram API' do
        result = adapter.send_message(to: chat_id, content: content)
        
        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:response]).to eq(telegram_response["result"])

        expected_uri = URI("https://api.telegram.org/bot#{bot_token}/sendMessage")
        expected_body = {
          chat_id: chat_id,
          text: content,
          parse_mode: "Markdown"
        }

        expect(adapter).to have_received(:post_json).with(expected_uri, expected_body)
      end

      it 'logs outbound message' do
        expect {
          result = adapter.send_message(to: chat_id, content: content)
          
          expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        }.to change(OutboundMessage, :count).by(1)

        outbound = OutboundMessage.last
        expect(outbound.recipient).to eq(chat_id)
        expect(outbound.content).to eq(content)
        expect(outbound.metadata["message_id"]).to eq(54321)
      end

      it 'supports parse_mode option' do
        adapter.send_message(to: chat_id, content: content, parse_mode: "HTML")
        
        expect(adapter).to have_received(:post_json) do |uri, body|
          expect(body[:parse_mode]).to eq("HTML")
        end
      end

      it 'defaults to Markdown parse_mode' do
        adapter.send_message(to: chat_id, content: content)
        
        expect(adapter).to have_received(:post_json) do |uri, body|
          expect(body[:parse_mode]).to eq("Markdown")
        end
      end

      it 'supports reply_to option' do
        adapter.send_message(to: chat_id, content: content, reply_to: 12345)
        
        expect(adapter).to have_received(:post_json) do |uri, body|
          expect(body[:reply_to_message_id]).to eq(12345)
        end
      end

      it 'supports silent option' do
        adapter.send_message(to: chat_id, content: content, silent: true)
        
        expect(adapter).to have_received(:post_json) do |uri, body|
          expect(body[:disable_notification]).to be true
        end
      end

      it 'omits optional fields when not specified' do
        adapter.send_message(to: chat_id, content: content)
        
        expect(adapter).to have_received(:post_json) do |uri, body|
          expect(body).not_to have_key(:reply_to_message_id)
          expect(body).not_to have_key(:disable_notification)
        end
      end
    end

    context 'when bot token is not configured' do
      before do
        allow(VaultEntry).to receive(:find_by).and_return(nil)
      end

      it 'returns failure with error message' do
        result = adapter.send_message(to: chat_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Telegram bot token not configured")
      end

      it 'does not make API call' do
        expect(adapter).not_to receive(:post_json)
        adapter.send_message(to: chat_id, content: content)
      end

      it 'does not log outbound message' do
        expect {
          adapter.send_message(to: chat_id, content: content)
        }.not_to change(OutboundMessage, :count)
      end
    end

    context 'when Telegram API returns error' do
      let(:error_response) do
        {
          "ok" => false,
          "error_code" => 400,
          "description" => "Bad Request: chat not found"
        }
      end

      before do
        allow(adapter).to receive(:post_json).and_return(error_response)
      end

      it 'returns failure with API error' do
        result = adapter.send_message(to: chat_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Telegram API: Bad Request: chat not found")
      end

      it 'does not log outbound message on API error' do
        expect {
          adapter.send_message(to: chat_id, content: content)
        }.not_to change(OutboundMessage, :count)
      end
    end
  end

  describe '#react' do
    let(:message_id) { 12345 }
    let(:emoji) { "👍" }
    let(:chat_id) { "-100123456789" }
    let(:bot_token) { "123456789:ABCdefGHIjklMNOpqrSTUvwxYZ" }

    before do
      allow(VaultEntry).to receive(:find_by).and_return(double(value: bot_token))
    end

    context 'with successful reaction' do
      before do
        allow(adapter).to receive(:post_json).and_return({ "ok" => true })
      end

      it 'sends reaction to specified chat' do
        result = adapter.react(message_id: message_id, emoji: emoji, chat_id: chat_id)
        
        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true

        expected_uri = URI("https://api.telegram.org/bot#{bot_token}/setMessageReaction")
        expected_body = {
          chat_id: chat_id,
          message_id: message_id,
          reaction: [{ type: "emoji", emoji: emoji }]
        }

        expect(adapter).to have_received(:post_json).with(expected_uri, expected_body)
      end

      it 'uses default chat_id from channel config when not specified' do
        result = adapter.react(message_id: message_id, emoji: emoji)
        
        expect(result.success?).to be true
        expect(adapter).to have_received(:post_json) do |uri, body|
          expect(body[:chat_id]).to eq("123456789") # from channel config
        end
      end
    end

    context 'when bot token is not configured' do
      before do
        allow(VaultEntry).to receive(:find_by).and_return(nil)
      end

      it 'returns failure' do
        result = adapter.react(message_id: message_id, emoji: emoji, chat_id: chat_id)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Bot token not configured")
      end
    end

    context 'when no chat_id is available' do
      let(:channel_without_config) { create(:channel, channel_type: 'telegram', config: nil) }
      let(:adapter_without_config) { described_class.new(channel_without_config) }

      it 'returns failure when no chat_id provided and no default' do
        result = adapter_without_config.react(message_id: message_id, emoji: emoji)
        
        expect(result.success?).to be false
        expect(result.error).to eq("No chat_id for reaction")
      end
    end

    context 'when API returns error' do
      before do
        allow(adapter).to receive(:post_json).and_return({
          "ok" => false,
          "description" => "Bad Request: message to react not found"
        })
      end

      it 'returns failure with API error' do
        result = adapter.react(message_id: message_id, emoji: emoji, chat_id: chat_id)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Bad Request: message to react not found")
      end
    end
  end

  describe '#verify_webhook' do
    let(:webhook_secret) { "webhook_secret_123" }
    let(:channel_with_secret) do
      create(:channel, 
             channel_type: 'telegram',
             config: { "webhook_secret" => webhook_secret })
    end
    let(:adapter_with_secret) { described_class.new(channel_with_secret) }

    context 'with valid secret token' do
      let(:request) do
        double('request',
               headers: { "X-Telegram-Bot-Api-Secret-Token" => webhook_secret })
      end

      it 'returns true for matching secret' do
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be true
      end
    end

    context 'with invalid secret token' do
      let(:request) do
        double('request',
               headers: { "X-Telegram-Bot-Api-Secret-Token" => "wrong_secret" })
      end

      it 'returns false for non-matching secret' do
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be false
      end
    end

    context 'with missing secret token header' do
      let(:request) { double('request', headers: {}) }

      it 'returns false when header is missing' do
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be false
      end
    end

    context 'when no webhook secret is configured' do
      let(:request) { double('request', headers: {}) }

      it 'returns true (no verification in dev mode)' do
        result = adapter.verify_webhook(request)
        expect(result).to be true
      end
    end

    context 'when channel config is nil' do
      let(:channel_no_config) { create(:channel, channel_type: 'telegram', config: nil) }
      let(:adapter_no_config) { described_class.new(channel_no_config) }
      let(:request) { double('request', headers: {}) }

      it 'returns true when config is nil' do
        result = adapter_no_config.verify_webhook(request)
        expect(result).to be true
      end
    end
  end

  describe '#post_json' do
    let(:uri) { URI("https://api.telegram.org/bot123/test") }
    let(:body) { { test: "data" } }
    let(:mock_http) { double('http') }
    let(:mock_request) { double('request') }
    let(:mock_response) { double('response', body: '{"ok": true}') }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:open_timeout=)
      allow(mock_http).to receive(:read_timeout=)
      allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
      allow(mock_request).to receive(:[]=)
      allow(mock_request).to receive(:body=)
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    it 'configures HTTP client correctly' do
      adapter.send(:post_json, uri, body)

      expect(Net::HTTP).to have_received(:new).with(uri.host, uri.port)
      expect(mock_http).to have_received(:use_ssl=).with(true)
      expect(mock_http).to have_received(:open_timeout=).with(10)
      expect(mock_http).to have_received(:read_timeout=).with(15)
    end

    it 'sets correct headers and body' do
      adapter.send(:post_json, uri, body)

      expect(mock_request).to have_received(:[]=).with("Content-Type", "application/json")
      expect(mock_request).to have_received(:body=).with(body.to_json)
    end

    it 'returns parsed JSON response' do
      result = adapter.send(:post_json, uri, body)
      expect(result).to eq({ "ok" => true })
    end

    context 'when HTTP request raises exception' do
      before do
        allow(mock_http).to receive(:request).and_raise(Net::TimeoutError, "Request timeout")
      end

      it 'returns error response' do
        result = adapter.send(:post_json, uri, body)
        
        expect(result).to eq({
          "ok" => false,
          "description" => "Request timeout"
        })
      end
    end

    context 'when JSON parsing fails' do
      before do
        allow(mock_response).to receive(:body).and_return("invalid json")
        allow(JSON).to receive(:parse).and_raise(JSON::ParserError, "Invalid JSON")
      end

      it 'returns error response' do
        result = adapter.send(:post_json, uri, body)
        
        expect(result).to eq({
          "ok" => false,
          "description" => "Invalid JSON"
        })
      end
    end
  end

  describe 'private methods' do
    describe '#bot_token' do
      context 'when token exists in vault' do
        let(:token) { "123456789:ABCdefGHIjklMNOpqrSTUvwxYZ" }

        before do
          allow(VaultEntry).to receive(:find_by).with(
            namespace: "channel_credentials",
            key: "telegram_bot_token"
          ).and_return(double(value: token))
        end

        it 'retrieves token from vault' do
          result = adapter.send(:bot_token)
          expect(result).to eq(token)
        end
      end

      context 'when token does not exist' do
        before do
          allow(VaultEntry).to receive(:find_by).and_return(nil)
        end

        it 'returns nil' do
          result = adapter.send(:bot_token)
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
      expect(adapter).to respond_to(:log_inbound_message)
      expect(adapter).to respond_to(:log_outbound_message)
    end
  end

  describe 'constants' do
    it 'defines BASE_URL constant' do
      expect(described_class::BASE_URL).to eq("https://api.telegram.org")
    end
  end
end