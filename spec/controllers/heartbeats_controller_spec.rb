# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HeartbeatsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before { sign_in user }

  describe 'GET #index' do
    it 'returns a successful response with default config' do
      get :index
      expect(response).to be_successful
      expect(assigns(:config)).to include('enabled' => false)
    end

    it 'loads saved config' do
      Setting.set('heartbeat', { enabled: true, model: 'gpt-4', interval_minutes: 60, prompt: 'test' }.to_json)
      get :index
      expect(assigns(:config)['enabled']).to be true
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'PATCH #update' do
    it 'saves settings and redirects' do
      patch :update, params: { enabled: '1', model: 'gpt-4', interval_minutes: '60', prompt: 'check in' }
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:notice]).to include('saved')

      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['enabled']).to be true
      expect(config['interval_minutes']).to eq(60)
    end

    it 'clamps interval to valid range' do
      patch :update, params: { enabled: '0', interval_minutes: '1' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['interval_minutes']).to eq(5)

      patch :update, params: { enabled: '0', interval_minutes: '9999' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['interval_minutes']).to eq(1440)
    end
  end

  describe 'POST #trigger' do
    it 'enqueues heartbeat job and redirects' do
      expect(HeartbeatJob).to receive(:perform_later)
      post :trigger
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:notice]).to include('triggered')
    end
  end
end
