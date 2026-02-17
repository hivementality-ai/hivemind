# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlatformController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user

    # Mock external service checks
    allow(Redis).to receive(:new).and_return(double(ping: 'PONG'))
    allow(Sidekiq::ProcessSet).to receive(:new).and_return(double(size: 1))
    allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
    allow(File).to receive(:directory?).and_call_original
    allow(File).to receive(:directory?).with('/workspace').and_return(false)
  end

  describe 'GET #status' do
    it 'returns a successful response' do
      get :status
      expect(response).to be_successful
    end

    it 'assigns stats with expected keys' do
      create(:agent, enabled: true)
      get :status
      stats = assigns(:stats)
      expect(stats).to include(:agents, :agents_enabled, :teams, :sessions, :memories, :tools)
    end

    it 'assigns providers' do
      create(:provider_config, :openai)
      get :status
      expect(assigns(:providers)).to be_an(Array)
    end

    it 'assigns services' do
      get :status
      expect(assigns(:services)).to be_an(Array)
    end

    it 'assigns cost stats' do
      get :status
      expect(assigns(:cost_today)).to be_a(Numeric)
      expect(assigns(:cost_week)).to be_a(Numeric)
      expect(assigns(:cost_month)).to be_a(Numeric)
    end

    it 'handles Redis connection failure' do
      allow(Redis).to receive(:new).and_raise(StandardError)
      get :status
      expect(assigns(:redis_connected)).to be false
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :status
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
