# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhooksController, type: :controller do
  let(:channel) { create(:channel, :telegram, enabled: true, config: { 'verify_token' => 'my_token' }) }
  let(:adapter) { double('adapter', verify_webhook: true) }

  before do
    allow(Channels::Registry).to receive(:adapter_for).and_return(adapter)
  end

  describe 'GET #verify' do
    context 'with valid WhatsApp challenge' do
      it 'returns the challenge' do
        get :verify, params: {
          channel_type: channel.channel_type,
          'hub.mode' => 'subscribe',
          'hub.verify_token' => 'my_token',
          'hub.challenge' => 'challenge_code'
        }
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq('challenge_code')
      end
    end

    context 'with invalid verify token' do
      it 'returns forbidden' do
        get :verify, params: {
          channel_type: channel.channel_type,
          'hub.mode' => 'subscribe',
          'hub.verify_token' => 'wrong'
        }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #receive' do
    context 'with successful processing' do
      it 'returns ok' do
        result = double(success?: true, data: {})
        allow(adapter).to receive(:receive).and_return(result)

        post :receive, params: { channel_type: channel.channel_type, message: 'hello' }
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with Slack challenge' do
      it 'returns the challenge' do
        result = double(success?: true, data: { challenge: 'slack_challenge' })
        allow(adapter).to receive(:receive).and_return(result)

        post :receive, params: { channel_type: channel.channel_type }
        expect(response.parsed_body['challenge']).to eq('slack_challenge')
      end
    end

    context 'with inbound message' do
      it 'enqueues InboundMessageJob' do
        msg = double(id: 1)
        result = double(success?: true, data: { inbound_message: msg })
        allow(adapter).to receive(:receive).and_return(result)

        expect(InboundMessageJob).to receive(:perform_later).with(1)
        post :receive, params: { channel_type: channel.channel_type }
      end
    end

    context 'when processing fails' do
      it 'returns unprocessable_entity' do
        result = double(success?: false, error: 'bad data')
        allow(adapter).to receive(:receive).and_return(result)

        post :receive, params: { channel_type: channel.channel_type }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when an exception is raised' do
      it 'returns internal_server_error' do
        allow(adapter).to receive(:receive).and_raise(StandardError, 'boom')

        post :receive, params: { channel_type: channel.channel_type }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  context 'when channel not found' do
    it 'returns 404' do
      get :verify, params: { channel_type: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when webhook signature is invalid' do
    it 'returns 401' do
      allow(adapter).to receive(:verify_webhook).and_return(false)
      get :verify, params: { channel_type: channel.channel_type }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
