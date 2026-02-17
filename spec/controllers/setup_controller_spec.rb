# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SetupController, type: :controller do
  before do
    # Ensure setup is not marked complete
    Setting.find_by(key: 'setup_complete')&.destroy
  end

  describe 'GET #index' do
    it 'redirects to account step' do
      get :index
      expect(response).to redirect_to(setup_account_path)
    end

    context 'when setup is complete' do
      before { Setting.set('setup_complete', 'true') }

      it 'redirects to root' do
        get :index
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'GET #account' do
    it 'returns a successful response' do
      get :account
      expect(response).to be_successful
    end

    it 'redirects to provider if already signed in' do
      user = create(:user, :owner)
      sign_in user
      get :account
      expect(response).to redirect_to(setup_provider_path)
    end
  end

  describe 'POST #create_account' do
    it 'creates user and redirects to provider' do
      expect {
        post :create_account, params: { user: { email: 'test@example.com', password: 'password123', password_confirmation: 'password123' } }
      }.to change(User, :count).by(1)
      expect(response).to redirect_to(setup_provider_path)
      expect(User.last.role).to eq('owner')
    end

    context 'with invalid params' do
      it 'renders account form' do
        post :create_account, params: { user: { email: '', password: '' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  context 'when authenticated' do
    let(:user) { create(:user, :owner) }

    before { sign_in user }

    describe 'GET #provider' do
      it 'returns a successful response' do
        get :provider
        expect(response).to be_successful
      end
    end

    describe 'POST #save_provider' do
      it 'saves provider and redirects to team' do
        post :save_provider, params: {
          providers: {
            anthropic: { api_key: 'sk-test-123', default_model: 'claude-sonnet-4-5', models: [ 'claude-sonnet-4-5' ] }
          }
        }
        expect(response).to redirect_to(setup_team_path)
        expect(VaultEntry.find_by(namespace: 'providers', key: 'anthropic_api_key')).to be_present
      end

      it 'renders provider if no keys provided' do
        post :save_provider, params: { providers: { anthropic: { api_key: '' } } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe 'GET #team' do
      it 'returns a successful response' do
        get :team
        expect(response).to be_successful
      end
    end

    describe 'POST #save_team' do
      it 'creates team and redirects to agent' do
        expect {
          post :save_team, params: { team: { name: 'My Team', description: 'Desc' } }
        }.to change(Team, :count).by(1)
        expect(response).to redirect_to(setup_agent_path(team_id: Team.last.id))
      end

      context 'with invalid params' do
        it 'renders team form' do
          post :save_team, params: { team: { name: '' } }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe 'GET #agent' do
      let(:team) { create(:team) }

      it 'returns a successful response' do
        get :agent, params: { team_id: team.id }
        expect(response).to be_successful
      end
    end

    describe 'POST #save_agent' do
      let(:team) { create(:team) }
      let(:template) { create(:agent_template) }

      before do
        create(:provider_config, :openai)
      end

      it 'creates agent and marks setup complete' do
        expect {
          post :save_agent, params: { agent: { name: 'Bot', template_id: template.id, team_id: team.id } }
        }.to change(Agent, :count).by(1)
        expect(response).to redirect_to(setup_complete_path)
        expect(Setting.get('setup_complete')).to eq('true')
      end

      context 'with invalid params' do
        it 'renders agent form' do
          allow_any_instance_of(Agent).to receive(:save).and_return(false)
          post :save_agent, params: { agent: { name: '', template_id: template.id, team_id: team.id } }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    describe 'GET #complete' do
      it 'returns a successful response' do
        Setting.set('setup_complete', 'true')
        create(:agent)
        get :complete
        expect(response).to be_successful
      end
    end
  end
end
