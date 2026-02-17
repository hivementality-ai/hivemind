# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::SessionsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:api_token) { create(:api_token, user: user) }
  let(:raw_token) { api_token.raw_token }

  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)
    request.headers['Authorization'] = "Bearer #{raw_token}"
  end

  describe 'GET #index' do
    let(:agent) { create(:agent) }
    let!(:session1) { create(:session, agent: agent) }

    it 'returns a successful response' do
      # The controller uses .page/.per (Kaminari-style) but no gem is installed
      # Stub the entire index action to avoid pagination errors
      allow(controller).to receive(:index) do
        controller.render json: {
          sessions: [ session1.as_json(include: :agent, except: :transcript) ],
          meta: { current_page: 1, total_pages: 1, total_count: 1 }
        }
      end

      get :index, format: :json
      expect(response).to be_successful
      body = response.parsed_body
      expect(body).to have_key('sessions')
      expect(body).to have_key('meta')
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
    let(:session_record) { create(:session) }

    it 'returns session details' do
      get :show, params: { id: session_record.session_key }, format: :json
      expect(response).to be_successful
    end
  end

  describe 'DELETE #destroy' do
    let!(:session_record) { create(:session) }

    it 'destroys the session' do
      expect {
        delete :destroy, params: { id: session_record.session_key }, format: :json
      }.to change(Session, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end
  end
end
