# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DashboardController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
  end

  describe 'GET #index' do
    let!(:agent1) { create(:agent, name: "Alpha") }
    let!(:agent2) { create(:agent, name: "Beta") }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns @agents' do
      get :index
      expect(assigns(:agents).map(&:name)).to match_array(%w[Alpha Beta])
    end

    it 'orders agents by name' do
      get :index
      agents = assigns(:agents)
      expect(agents.first.name).to eq("Alpha")
      expect(agents.last.name).to eq("Beta")
    end

    it 'assigns @recent_activity' do
      get :index
      expect(assigns(:recent_activity)).to be_an(Array)
    end

    it 'assigns @cost_summary' do
      get :index
      expect(assigns(:cost_summary)).to be_an(Array)
    end

    context 'when not authenticated and setup not complete' do
      before do
        sign_out user
        Setting.set("setup_complete", nil)
      end

      it 'redirects to setup' do
        get :index
        expect(response).to redirect_to(setup_path)
      end
    end

    context 'when not authenticated but setup complete' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
