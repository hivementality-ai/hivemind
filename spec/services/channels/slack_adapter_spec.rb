# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::SlackAdapter do
  let(:channel) { create(:channel, channel_type: 'slack', config: { "default_channel_id" => "C123456789" }) }
  let(:adapter) { described_class.new(channel) }

  describe '#receive' do
    context 'with URL verification challenge' do
      let(:url_verification) do
        {
          token: "verification_token",
          challenge: "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P",
          type: "url_verification"
        }
      end

      it 'returns the challenge for URL verification' do
        result = adapter.receive(url_verification)

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:challenge]).to eq("3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P")
      end

      it 'does not log inbound message for URL verification' do
        expect {
          adapter.receive(url_verification)
        }.not_to change(InboundMessage, :count)
      end
    end

    context 'with valid Slack message event' do
      let(:slack_message) do
        {
          token: "verification_token",
          team_id: "T123456",
          api_app_id: "A123456",
          event: {
            type: "message",
            user: "U123456789",
            text: "Hello bot!",
            ts: "1640995200.123456",
            channel: "C123456789",
            event_ts: "1640995200.123456"
          },
          type: "event_callback"
        }
      end

      it 'processes the message and logs inbound message' do
        expect {
          result = adapter.receive(slack_message)
          
          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true
          expect(result.data[:inbound_message]).to be_a(InboundMessage)
        }.to change(InboundMessage, :count).by(1)

        inbound = InboundMessage.last
        expect(inbound.external_id).to eq("1640995200.123456")
        expect(inbound.sender).to eq("U123456789")
        expect(inbound.content).to eq("Hello bot!")
        expect(inbound.metadata["channel_id"]).to eq("C123456789")
        expect(inbound.metadata["event_type"]).to eq("message")
        expect(inbound.metadata["team_id"]).to eq("T123456")
      end

      it 'handles thread messages' do
        threaded_message = slack_message.deep_dup
        threaded_message[:event][:thread_ts] = "1640995000.111111"

        result = adapter.receive(threaded_message)
        
        expect(result.success?).to be true
        inbound = InboundMessage.last
        expect(inbound.metadata["thread_ts"]).to eq("1640995000.111111")
      end

      it 'handles string keys in input' do
        string_message = {
          "team_id" => "T123456",
          "event" => {
            "type" => "message",
            "user" => "U123456789",
            "text" => "Hello bot!",
            "ts" => "1640995200.123456",
            "channel" => "C123456789"
          },
          "type" => "event_callback"
        }

        result = adapter.receive(string_message)
        
        expect(result.success?).to be true
        expect(InboundMessage.last.content).to eq("Hello bot!")
      end

      it 'handles missing text field' do
        message_without_text = slack_message.deep_dup
        message_without_text[:event].delete(:text)

        result = adapter.receive(message_without_text)
        
        expect(result.success?).to be true
        expect(InboundMessage.last.content).to eq("") # nil.to_s
      end
    end

    context 'with bot message' do
      let(:bot_message) do
        {
          event: {
            type: "message",
            bot_id: "B123456789",
            text: "Bot message",
            ts: "1640995200.123456",
            channel: "C123456789"
          },
          type: "event_callback"
        }
      end

      it 'skips bot messages' do
        result = adapter.receive(bot_message)
        
        expect(result.success?).to be true
        expect(result.data[:skipped]).to be true
      end

      it 'does not create inbound message for bot messages' do
        expect {
          adapter.receive(bot_message)
        }.not_to change(InboundMessage, :count)
      end
    end

    context 'with event without event data' do
      let(:empty_event) do
        {
          type: "event_callback",
          team_id: "T123456"
          # Missing event key
        }
      end

      it 'skips processing and returns success' do
        result = adapter.receive(empty_event)
        
        expect(result.success?).to be true
        expect(result.data[:skipped]).to be true
      end
    end

    context 'when logging fails' do
      before do
        allow_any_instance_of(described_class).to receive(:log_inbound_message).and_raise(StandardError, "Database error")
      end

      it 'returns failure with error message' do
        slack_message = {
          event: {
            type: "message",
            user: "U123456789",
            text: "Hello bot!",
            ts: "1640995200.123456",
            channel: "C123456789"
          }
        }

        result = adapter.receive(slack_message)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Slack receive failed: Database error")
      end
    end
  end

  describe '#send_message' do
    let(:channel_id) { "C123456789" }
    let(:content) { "Hello from bot!" }
    let(:bot_token) { "xoxb-123-456-789" }

    before do
      # Mock vault entry for bot token
      allow(VaultEntry).to receive(:find_by).with(
        namespace: "channel_credentials",
        key: "slack_bot_token"
      ).and_return(double(value: bot_token))
    end

    context 'with successful Slack API response' do
      let(:slack_response) do
        {
          "ok" => true,
          "channel" => channel_id,
          "ts" => "1640995200.123456",
          "message" => {
            "type" => "message",
            "user" => "U123456789",
            "text" => content,
            "ts" => "1640995200.123456"
          }
        }
      end

      before do
        allow(adapter).to receive(:slack_post).and_return(slack_response)
      end

      it 'sends message to Slack API' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:response]).to eq(slack_response)

        expected_body = {
          channel: channel_id,
          text: content
        }

        expect(adapter).to have_received(:slack_post).with("chat.postMessage", expected_body, bot_token)
      end

      it 'logs outbound message' do
        expect {
          result = adapter.send_message(to: channel_id, content: content)
          
          expect(result.data[:outbound_message]).to be_a(OutboundMessage)
        }.to change(OutboundMessage, :count).by(1)

        outbound = OutboundMessage.last
        expect(outbound.recipient).to eq(channel_id)
        expect(outbound.content).to eq(content)
        expect(outbound.metadata["ts"]).to eq("1640995200.123456")
        expect(outbound.metadata["channel"]).to eq(channel_id)
      end

      it 'supports thread_ts option' do
        adapter.send_message(to: channel_id, content: content, thread_ts: "1640995000.111111")
        
        expect(adapter).to have_received(:slack_post) do |method, body, token|
          expect(body[:thread_ts]).to eq("1640995000.111111")
        end
      end

      it 'supports blocks option' do
        blocks = [{ type: "section", text: { type: "mrkdwn", text: "Hello *world*!" } }]
        
        adapter.send_message(to: channel_id, content: content, blocks: blocks)
        
        expect(adapter).to have_received(:slack_post) do |method, body, token|
          expect(body[:blocks]).to eq(blocks)
        end
      end

      it 'supports no_unfurl option' do
        adapter.send_message(to: channel_id, content: content, no_unfurl: true)
        
        expect(adapter).to have_received(:slack_post) do |method, body, token|
          expect(body[:unfurl_links]).to be false
        end
      end

      it 'omits optional fields when not specified' do
        adapter.send_message(to: channel_id, content: content)
        
        expect(adapter).to have_received(:slack_post) do |method, body, token|
          expect(body).not_to have_key(:thread_ts)
          expect(body).not_to have_key(:blocks)
          expect(body).not_to have_key(:unfurl_links)
        end
      end
    end

    context 'when bot token is not configured' do
      before do
        allow(VaultEntry).to receive(:find_by).and_return(nil)
      end

      it 'returns failure with error message' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Slack bot token not configured")
      end

      it 'does not make API call' do
        expect(adapter).not_to receive(:slack_post)
        adapter.send_message(to: channel_id, content: content)
      end

      it 'does not log outbound message' do
        expect {
          adapter.send_message(to: channel_id, content: content)
        }.not_to change(OutboundMessage, :count)
      end
    end

    context 'when Slack API returns error' do
      let(:error_response) do
        {
          "ok" => false,
          "error" => "channel_not_found"
        }
      end

      before do
        allow(adapter).to receive(:slack_post).and_return(error_response)
      end

      it 'returns failure with API error' do
        result = adapter.send_message(to: channel_id, content: content)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Slack API: channel_not_found")
      end

      it 'does not log outbound message on API error' do
        expect {
          adapter.send_message(to: channel_id, content: content)
        }.not_to change(OutboundMessage, :count)
      end
    end
  end

  describe '#react' do
    let(:message_id) { "1640995200.123456" }
    let(:emoji) { "thumbsup" }
    let(:channel_id) { "C123456789" }
    let(:bot_token) { "xoxb-123-456-789" }

    before do
      allow(VaultEntry).to receive(:find_by).and_return(double(value: bot_token))
    end

    context 'with successful reaction' do
      before do
        allow(adapter).to receive(:slack_post).and_return({ "ok" => true })
      end

      it 'sends reaction to specified channel' do
        result = adapter.react(message_id: message_id, emoji: emoji, channel_id: channel_id)
        
        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true

        expected_body = {
          channel: channel_id,
          timestamp: message_id,
          name: emoji
        }

        expect(adapter).to have_received(:slack_post).with("reactions.add", expected_body, bot_token)
      end

      it 'uses default channel_id from channel config when not specified' do
        result = adapter.react(message_id: message_id, emoji: emoji)
        
        expect(result.success?).to be true
        expect(adapter).to have_received(:slack_post) do |method, body, token|
          expect(body[:channel]).to eq("C123456789") # from channel config
        end
      end

      it 'strips colons from emoji names' do
        adapter.react(message_id: message_id, emoji: ":thumbsup:", channel_id: channel_id)
        
        expect(adapter).to have_received(:slack_post) do |method, body, token|
          expect(body[:name]).to eq("thumbsup")
        end
      end

      it 'handles emoji without colons' do
        adapter.react(message_id: message_id, emoji: "thumbsup", channel_id: channel_id)
        
        expect(adapter).to have_received(:slack_post) do |method, body, token|
          expect(body[:name]).to eq("thumbsup")
        end
      end
    end

    context 'when bot token is not configured' do
      before do
        allow(VaultEntry).to receive(:find_by).and_return(nil)
      end

      it 'returns failure' do
        result = adapter.react(message_id: message_id, emoji: emoji, channel_id: channel_id)
        
        expect(result.success?).to be false
        expect(result.error).to eq("Bot token not configured")
      end
    end

    context 'when no channel_id is available' do
      let(:channel_without_config) { create(:channel, channel_type: 'slack', config: nil) }
      let(:adapter_without_config) { described_class.new(channel_without_config) }

      it 'returns failure when no channel_id provided and no default' do
        result = adapter_without_config.react(message_id: message_id, emoji: emoji)
        
        expect(result.success?).to be false
        expect(result.error).to eq("No channel_id for reaction")
      end
    end

    context 'when API returns error' do
      before do
        allow(adapter).to receive(:slack_post).and_return({
          "ok" => false,
          "error" => "already_reacted"
        })
      end

      it 'returns failure with API error' do
        result = adapter.react(message_id: message_id, emoji: emoji, channel_id: channel_id)
        
        expect(result.success?).to be false
        expect(result.error).to eq("already_reacted")
      end
    end
  end

  describe '#verify_webhook' do
    let(:signing_secret) { "slack_signing_secret_123" }
    let(:timestamp) { Time.now.to_i.to_s }
    let(:body_content) { '{"type":"event_callback","event":{"text":"hello"}}' }
    let(:sig_basestring) { "v0:#{timestamp}:#{body_content}" }
    let(:signature) { "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, sig_basestring)}" }

    let(:channel_with_secret) do
      create(:channel, 
             channel_type: 'slack',
             config: { "signing_secret" => signing_secret })
    end
    let(:adapter_with_secret) { described_class.new(channel_with_secret) }

    context 'with valid signature' do
      let(:request) do
        double('request',
               headers: {
                 "X-Slack-Request-Timestamp" => timestamp,
                 "X-Slack-Signature" => signature
               },
               raw_post: body_content)
      end

      it 'returns true for valid signature' do
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be true
      end
    end

    context 'with invalid signature' do
      let(:request) do
        double('request',
               headers: {
                 "X-Slack-Request-Timestamp" => timestamp,
                 "X-Slack-Signature" => "v0=invalid_signature"
               },
               raw_post: body_content)
      end

      it 'returns false for invalid signature' do
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be false
      end
    end

    context 'with missing headers' do
      it 'returns false when timestamp header is missing' do
        request = double('request',
                        headers: { "X-Slack-Signature" => signature },
                        raw_post: body_content)
        
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be false
      end

      it 'returns false when signature header is missing' do
        request = double('request',
                        headers: { "X-Slack-Request-Timestamp" => timestamp },
                        raw_post: body_content)
        
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be false
      end

      it 'returns false when both headers are missing' do
        request = double('request', headers: {}, raw_post: body_content)
        
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be false
      end
    end

    context 'with old timestamp' do
      let(:old_timestamp) { (Time.now - 400).to_i.to_s } # 400 seconds ago
      let(:old_sig_basestring) { "v0:#{old_timestamp}:#{body_content}" }
      let(:old_signature) { "v0=#{OpenSSL::HMAC.hexdigest('SHA256', signing_secret, old_sig_basestring)}" }
      let(:request) do
        double('request',
               headers: {
                 "X-Slack-Request-Timestamp" => old_timestamp,
                 "X-Slack-Signature" => old_signature
               },
               raw_post: body_content)
      end

      it 'returns false for requests older than 5 minutes' do
        result = adapter_with_secret.verify_webhook(request)
        expect(result).to be false
      end
    end

    context 'when no signing secret is configured' do
      let(:request) { double('request', headers: {}) }

      it 'returns true (no verification in dev mode)' do
        result = adapter.verify_webhook(request)
        expect(result).to be true
      end
    end

    context 'when channel config is nil' do
      let(:channel_no_config) { create(:channel, channel_type: 'slack', config: nil) }
      let(:adapter_no_config) { described_class.new(channel_no_config) }
      let(:request) { double('request', headers: {}) }

      it 'returns true when config is nil' do
        result = adapter_no_config.verify_webhook(request)
        expect(result).to be true
      end
    end
  end

  describe '#slack_post' do
    let(:method) { "chat.postMessage" }
    let(:body) { { channel: "C123", text: "test" } }
    let(:token) { "xoxb-123-456" }
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
      adapter.send(:slack_post, method, body, token)

      uri = URI("https://slack.com/api/#{method}")
      expect(Net::HTTP).to have_received(:new).with(uri.host, uri.port)
      expect(mock_http).to have_received(:use_ssl=).with(true)
      expect(mock_http).to have_received(:open_timeout=).with(10)
      expect(mock_http).to have_received(:read_timeout=).with(15)
    end

    it 'sets correct headers and body' do
      adapter.send(:slack_post, method, body, token)

      expect(mock_request).to have_received(:[]=).with("Authorization", "Bearer #{token}")
      expect(mock_request).to have_received(:[]=).with("Content-Type", "application/json")
      expect(mock_request).to have_received(:body=).with(body.to_json)
    end

    it 'returns parsed JSON response' do
      result = adapter.send(:slack_post, method, body, token)
      expect(result).to eq({ "ok" => true })
    end

    context 'when HTTP request raises exception' do
      before do
        allow(mock_http).to receive(:request).and_raise(Net::TimeoutError, "Request timeout")
      end

      it 'returns error response' do
        result = adapter.send(:slack_post, method, body, token)
        
        expect(result).to eq({
          "ok" => false,
          "error" => "Request timeout"
        })
      end
    end

    context 'when JSON parsing fails' do
      before do
        allow(mock_response).to receive(:body).and_return("invalid json")
        allow(JSON).to receive(:parse).and_raise(JSON::ParserError, "Invalid JSON")
      end

      it 'returns error response' do
        result = adapter.send(:slack_post, method, body, token)
        
        expect(result).to eq({
          "ok" => false,
          "error" => "Invalid JSON"
        })
      end
    end
  end

  describe 'private methods' do
    describe '#bot_token' do
      context 'when token exists in vault' do
        let(:token) { "xoxb-123-456-789" }

        before do
          allow(VaultEntry).to receive(:find_by).with(
            namespace: "channel_credentials",
            key: "slack_bot_token"
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
      expect(described_class::BASE_URL).to eq("https://slack.com/api")
    end
  end
end