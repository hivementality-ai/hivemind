# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::AgentsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:api_token) { create(:api_token, user: user) }
  let(:raw_token) { api_token.raw_token }

  before do
    api_token # ensure created
    # ApiController uses token auth, but ApplicationController's authenticate_user! also runs
    # We need to skip Devise auth and rely on API token auth
    allow(controller).to receive(:authenticate_user!).and_return(true)
    request.headers['Authorization'] = "Bearer #{raw_token}"
  end

  describe 'GET #index' do
    let!(:agent) { create(:agent) }

    it 'returns a successful response' do
      get :index, format: :json
      expect(response).to be_successful
      expect(response.parsed_body).to be_an(Array)
    end

    context 'when not authenticated' do
      before { request.headers['Authorization'] = nil }

      it 'returns unauthorized' do
        get :index, format: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET #show' do
    let(:agent) { create(:agent) }

    it 'returns agent details' do
      get :show, params: { slug: agent.slug }, format: :json
      expect(response).to be_successful
      expect(response.parsed_body['name']).to eq(agent.name)
    end

    it 'returns 404 for unknown slug' do
      get :show, params: { slug: 'nonexistent' }, format: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create' do
    let(:team) { create(:team) }

    it 'creates an agent' do
      expect {
        post :create, params: { agent: { name: 'New Bot', role: 'assistant', team_id: team.id } }, format: :json
      }.to change(Agent, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    context 'with invalid params' do
      it 'returns unprocessable_entity' do
        post :create, params: { agent: { name: '' } }, format: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH #update' do
    let(:agent) { create(:agent) }

    it 'updates the agent' do
      patch :update, params: { slug: agent.slug, agent: { name: 'Renamed' } }, format: :json
      expect(response).to be_successful
      expect(agent.reload.name).to eq('Renamed')
    end

    context 'with invalid params' do
      it 'returns unprocessable_entity' do
        allow_any_instance_of(Agent).to receive(:update).and_return(false)
        patch :update, params: { slug: agent.slug, agent: { name: '' } }, format: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:agent) { create(:agent) }

    it 'destroys the agent' do
      expect {
        delete :destroy, params: { slug: agent.slug }, format: :json
      }.to change(Agent, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
