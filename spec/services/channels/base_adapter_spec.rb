# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channels::BaseAdapter do
  let(:channel) { create(:channel, channel_type: 'test') }
  let(:adapter) { described_class.new(channel) }

  describe '#initialize' do
    it 'sets the channel' do
      expect(adapter.channel).to eq(channel)
    end
  end

  describe 'abstract methods' do
    describe '#receive' do
      it 'raises NotImplementedError' do
        expect {
          adapter.receive({})
        }.to raise_error(NotImplementedError, "Channels::BaseAdapter must implement #receive")
      end
    end

    describe '#send_message' do
      it 'raises NotImplementedError' do
        expect {
          adapter.send_message(to: "user123", content: "Hello")
        }.to raise_error(NotImplementedError, "Channels::BaseAdapter must implement #send_message")
      end
    end

    describe '#verify_webhook' do
      it 'raises NotImplementedError' do
        request = double('request')
        
        expect {
          adapter.verify_webhook(request)
        }.to raise_error(NotImplementedError, "Channels::BaseAdapter must implement #verify_webhook")
      end
    end
  end

  describe 'protected helper methods' do
    describe '#webhook_secret' do
      context 'when secret exists in vault' do
        let(:vault_entry) { double('vault_entry', encrypted_value: 'secret123') }

        before do
          allow(VaultEntry).to receive(:find_by).with(
            namespace: "channel_webhooks",
            key: "test_secret"
          ).and_return(vault_entry)
        end

        it 'retrieves secret from vault' do
          secret = adapter.send(:webhook_secret)
          expect(secret).to eq('secret123')
        end

        it 'caches the secret on subsequent calls' do
          adapter.send(:webhook_secret)
          adapter.send(:webhook_secret)
          
          expect(VaultEntry).to have_received(:find_by).once
        end
      end

      context 'when secret does not exist in vault' do
        before do
          allow(VaultEntry).to receive(:find_by).and_return(nil)
        end

        it 'returns nil' do
          secret = adapter.send(:webhook_secret)
          expect(secret).to be_nil
        end
      end
    end

    describe '#verify_hmac_signature' do
      let(:payload) { 'test payload' }
      let(:secret) { 'test_secret' }
      let(:valid_signature) { OpenSSL::HMAC.hexdigest('sha256', secret, payload) }

      before do
        allow(adapter).to receive(:webhook_secret).and_return(secret)
      end

      context 'with valid signature' do
        it 'returns true for matching HMAC' do
          result = adapter.send(:verify_hmac_signature, 
                               payload: payload, 
                               signature: valid_signature)
          
          expect(result).to be true
        end

        it 'uses SHA256 by default' do
          expect(OpenSSL::HMAC).to receive(:hexdigest).with('sha256', secret, payload).and_call_original
          
          adapter.send(:verify_hmac_signature, 
                      payload: payload, 
                      signature: valid_signature)
        end

        it 'accepts custom algorithm' do
          sha1_signature = OpenSSL::HMAC.hexdigest('sha1', secret, payload)
          
          result = adapter.send(:verify_hmac_signature,
                               payload: payload,
                               signature: sha1_signature,
                               algorithm: 'sha1')
          
          expect(result).to be true
        end
      end

      context 'with invalid signature' do
        it 'returns false for non-matching HMAC' do
          result = adapter.send(:verify_hmac_signature,
                               payload: payload,
                               signature: 'invalid_signature')
          
          expect(result).to be false
        end

        it 'returns false for empty signature' do
          result = adapter.send(:verify_hmac_signature,
                               payload: payload,
                               signature: '')
          
          expect(result).to be false
        end

        it 'returns false for nil signature' do
          result = adapter.send(:verify_hmac_signature,
                               payload: payload,
                               signature: nil)
          
          expect(result).to be false
        end
      end

      context 'when webhook secret is not available' do
        before do
          allow(adapter).to receive(:webhook_secret).and_return(nil)
        end

        it 'returns false' do
          result = adapter.send(:verify_hmac_signature,
                               payload: payload,
                               signature: valid_signature)
          
          expect(result).to be false
        end
      end

      it 'uses secure comparison' do
        expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).with(valid_signature, valid_signature).and_return(true)
        
        adapter.send(:verify_hmac_signature,
                    payload: payload,
                    signature: valid_signature)
      end
    end

    describe '#log_inbound_message' do
      it 'creates an InboundMessage record' do
        freeze_time do
          expect {
            adapter.send(:log_inbound_message,
                        external_id: 'msg_123',
                        sender: 'user456',
                        content: 'Hello world',
                        metadata: { platform: 'test' })
          }.to change(InboundMessage, :count).by(1)

          message = InboundMessage.last
          expect(message.channel_id).to eq(channel.id)
          expect(message.external_id).to eq('msg_123')
          expect(message.sender).to eq('user456')
          expect(message.content).to eq('Hello world')
          expect(message.metadata).to eq({ 'platform' => 'test' })
          expect(message.received_at).to eq(Time.current)
        end
      end

      it 'works with empty metadata' do
        expect {
          adapter.send(:log_inbound_message,
                      external_id: 'msg_123',
                      sender: 'user456',
                      content: 'Hello world')
        }.to change(InboundMessage, :count).by(1)

        message = InboundMessage.last
        expect(message.metadata).to eq({})
      end

      it 'handles complex metadata structures' do
        complex_metadata = {
          user: { id: 123, name: 'John' },
          message: { type: 'text', replied_to: 'msg_456' }
        }

        adapter.send(:log_inbound_message,
                    external_id: 'msg_123',
                    sender: 'user456',
                    content: 'Hello',
                    metadata: complex_metadata)

        message = InboundMessage.last
        expect(message.metadata).to eq(complex_metadata.deep_stringify_keys)
      end
    end

    describe '#log_outbound_message' do
      it 'creates an OutboundMessage record' do
        freeze_time do
          expect {
            adapter.send(:log_outbound_message,
                        recipient: 'user789',
                        content: 'Response message',
                        metadata: { response_to: 'msg_123' })
          }.to change(OutboundMessage, :count).by(1)

          message = OutboundMessage.last
          expect(message.channel_id).to eq(channel.id)
          expect(message.recipient).to eq('user789')
          expect(message.content).to eq('Response message')
          expect(message.metadata).to eq({ 'response_to' => 'msg_123' })
          expect(message.sent_at).to eq(Time.current)
        end
      end

      it 'works with empty metadata' do
        expect {
          adapter.send(:log_outbound_message,
                      recipient: 'user789',
                      content: 'Response message')
        }.to change(OutboundMessage, :count).by(1)

        message = OutboundMessage.last
        expect(message.metadata).to eq({})
      end

      it 'handles complex metadata structures' do
        complex_metadata = {
          delivery: { priority: 'high', retry_count: 0 },
          formatting: { markdown: true, mentions: ['@user123'] }
        }

        adapter.send(:log_outbound_message,
                    recipient: 'user789',
                    content: 'Complex message',
                    metadata: complex_metadata)

        message = OutboundMessage.last
        expect(message.metadata).to eq(complex_metadata.deep_stringify_keys)
      end
    end
  end

  describe 'inheritance behavior' do
    let(:concrete_adapter_class) do
      Class.new(described_class) do
        def receive(message)
          ServiceResponse.success(data: { processed: message })
        end

        def send_message(to:, content:, **options)
          log_outbound_message(recipient: to, content: content, metadata: options)
          ServiceResponse.success(data: { sent: true })
        end

        def verify_webhook(request)
          signature = request.headers['X-Signature']
          payload = request.body.read
          verify_hmac_signature(payload: payload, signature: signature)
        end
      end
    end

    let(:concrete_adapter) { concrete_adapter_class.new(channel) }

    it 'allows concrete implementations to override abstract methods' do
      result = concrete_adapter.receive({ text: 'Hello' })
      
      expect(result).to be_a(ServiceResponse)
      expect(result.success?).to be true
      expect(result.data[:processed]).to eq({ text: 'Hello' })
    end

    it 'allows concrete implementations to use helper methods' do
      expect {
        concrete_adapter.send_message(to: 'user123', content: 'Test message', priority: 'high')
      }.to change(OutboundMessage, :count).by(1)

      message = OutboundMessage.last
      expect(message.metadata).to eq({ 'priority' => 'high' })
    end

    it 'allows concrete implementations to use webhook verification' do
      secret = 'test_secret'
      payload = 'webhook_payload'
      signature = OpenSSL::HMAC.hexdigest('sha256', secret, payload)
      
      request = double('request',
                      headers: { 'X-Signature' => signature },
                      body: double(read: payload))
      
      allow(concrete_adapter).to receive(:webhook_secret).and_return(secret)
      
      result = concrete_adapter.verify_webhook(request)
      expect(result).to be true
    end
  end

  describe 'error handling in helper methods' do
    describe '#log_inbound_message' do
      it 'raises exception when required fields are missing' do
        expect {
          adapter.send(:log_inbound_message, external_id: nil, sender: 'user', content: 'test')
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe '#log_outbound_message' do
      it 'raises exception when required fields are missing' do
        expect {
          adapter.send(:log_outbound_message, recipient: nil, content: 'test')
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe '#verify_hmac_signature' do
      it 'handles OpenSSL exceptions gracefully' do
        allow(OpenSSL::HMAC).to receive(:hexdigest).and_raise(OpenSSL::OpenSSLError, "Invalid algorithm")
        allow(adapter).to receive(:webhook_secret).and_return('secret')
        
        expect {
          adapter.send(:verify_hmac_signature, payload: 'test', signature: 'sig')
        }.to raise_error(OpenSSL::OpenSSLError)
      end
    end
  end
end