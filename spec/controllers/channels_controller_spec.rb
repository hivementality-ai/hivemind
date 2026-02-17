# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChannelsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before { sign_in user }

  describe 'GET #index' do
    let!(:channel) { create(:channel) }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
      expect(assigns(:channels)).to eq([ channel ])
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #new' do
    it 'returns a successful response' do
      get :new
      expect(response).to be_successful
    end
  end

  describe 'POST #create' do
    let(:valid_params) { { channel: { name: 'Test', channel_type: 'telegram', enabled: true } } }

    it 'creates a channel and redirects' do
      expect {
        post :create, params: valid_params
      }.to change(Channel, :count).by(1)
      expect(response).to redirect_to(channels_path)
    end

    it 'stores credentials in vault' do
      post :create, params: valid_params.merge(credentials: { bot_token: 'secret123' })
      expect(VaultEntry.find_by(namespace: 'channel_credentials')).to be_present
    end

    context 'with invalid params' do
      it 'renders new' do
        post :create, params: { channel: { name: '', channel_type: '' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET #edit' do
    let(:channel) { create(:channel) }

    it 'returns a successful response' do
      get :edit, params: { id: channel.id }
      expect(response).to be_successful
    end
  end

  describe 'PATCH #update' do
    let(:channel) { create(:channel) }

    it 'updates and redirects' do
      patch :update, params: { id: channel.id, channel: { name: 'Updated' } }
      expect(response).to redirect_to(channels_path)
      expect(channel.reload.name).to eq('Updated')
    end

    it 'stores credentials on update' do
      patch :update, params: { id: channel.id, channel: { name: channel.name }, credentials: { api_key: 'new_key' } }
      expect(response).to redirect_to(channels_path)
    end

    it 'processes agent assignments' do
      agent = create(:agent)
      stub_request(:post, "https://slack.com/api/auth.test").to_return(
        status: 200, body: '{"ok":true,"user_id":"U123"}', headers: { 'Content-Type' => 'application/json' }
      )
      patch :update, params: {
        id: channel.id,
        channel: { name: channel.name },
        agent_assignments: { agent.id.to_s => { enabled: '1', bot_token: 'tok' } },
        default_agent: agent.id.to_s
      }
      expect(channel.agent_channels.count).to eq(1)
      expect(channel.agent_channels.first.is_default).to be true
    end

    context 'with invalid params' do
      it 'renders edit' do
        patch :update, params: { id: channel.id, channel: { name: '' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:channel) { create(:channel) }

    it 'destroys and redirects' do
      expect {
        delete :destroy, params: { id: channel.id }
      }.to change(Channel, :count).by(-1)
      expect(response).to redirect_to(channels_path)
    end
  end

  describe 'GET #connect' do
    let(:channel) { create(:channel, config: { 'connector_url' => 'http://localhost:3002' }) }

    it 'returns a successful response' do
      get :connect, params: { id: channel.id }
      expect(response).to be_successful
    end
  end
end
