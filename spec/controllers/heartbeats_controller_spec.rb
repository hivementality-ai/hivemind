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

    it 'assigns @provider_models from enabled providers with model_definitions' do
      create(:provider_config,
             name: "Anthropic",
             adapter_type: "anthropic",
             enabled: true,
             model_definitions: [ { "id" => "claude-haiku-4-5" } ])
      create(:provider_config,
             name: "Empty Provider",
             adapter_type: "openai",
             enabled: true,
             model_definitions: [])

      get :index

      groups = assigns(:provider_models)
      expect(groups.map { |g| g[:adapter_type] }).to include("anthropic")
      expect(groups.map { |g| g[:adapter_type] }).not_to include("openai")
    end

    it 'excludes disabled providers from @provider_models' do
      create(:provider_config,
             name: "Disabled Anthropic",
             adapter_type: "anthropic",
             enabled: false,
             model_definitions: [ { "id" => "claude-haiku-4-5" } ])

      get :index

      groups = assigns(:provider_models)
      expect(groups).to be_empty
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

    it 'saves provider alongside model' do
      patch :update, params: { enabled: '1', model: 'claude-haiku-4-5', provider: 'anthropic', interval_minutes: '30' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['model']).to eq('claude-haiku-4-5')
      expect(config['provider']).to eq('anthropic')
    end

    it 'stores nil provider when not submitted' do
      patch :update, params: { enabled: '1', model: 'gpt-4', interval_minutes: '30' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['provider']).to be_nil
    end

    it 'clamps interval to valid range' do
      patch :update, params: { enabled: '0', interval_minutes: '1' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['interval_minutes']).to eq(5)

      patch :update, params: { enabled: '0', interval_minutes: '9999' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['interval_minutes']).to eq(1440)
    end

    it 'saves light_context when enabled' do
      patch :update, params: { enabled: '1', model: 'gpt-4', interval_minutes: '30', light_context: '1' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['light_context']).to be true
    end

    it 'saves light_context as false when not submitted' do
      patch :update, params: { enabled: '1', model: 'gpt-4', interval_minutes: '30' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['light_context']).to be false
    end

    it 'disables heartbeat when enabled param is absent' do
      Setting.set('heartbeat', { 'enabled' => true }.to_json)
      patch :update, params: { model: 'gpt-4', interval_minutes: '30' }
      config = JSON.parse(Setting.get('heartbeat'))
      expect(config['enabled']).to be false
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
