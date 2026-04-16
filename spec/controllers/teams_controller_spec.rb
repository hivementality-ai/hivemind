# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TeamsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:team) { create(:team, name: "Engineering", description: "The eng team", custom_soul: "Be direct") }

  before do
    sign_in user
  end

  describe 'GET #index' do
    let!(:team_with_agents) { create(:team) }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns @teams' do
      get :index
      expect(assigns(:teams)).to include(team_with_agents)
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #edit' do
    it 'returns a successful response' do
      get :edit, params: { id: team.id }
      expect(response).to be_successful
    end

    it 'assigns @team' do
      get :edit, params: { id: team.id }
      expect(assigns(:team)).to eq(team)
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :edit, params: { id: team.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'PATCH #update' do
    it 'updates the team and redirects' do
      patch :update, params: { id: team.id, team: { name: "New Name", description: "New desc", custom_soul: "Be chill" } }
      expect(response).to redirect_to(teams_path)
      expect(flash[:notice]).to eq("New Name updated")
      team.reload
      expect(team.name).to eq("New Name")
      expect(team.description).to eq("New desc")
      expect(team.custom_soul).to eq("Be chill")
    end

    it 're-renders edit with invalid params' do
      patch :update, params: { id: team.id, team: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response).to render_template(:edit)
    end
  end
end
