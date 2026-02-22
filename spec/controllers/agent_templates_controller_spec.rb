# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentTemplatesController, type: :controller do
  let(:user) { create(:user, :owner) }

  before { sign_in user }

  describe 'GET #index' do
    let!(:template1) { create(:agent_template, category: 'coding') }
    let!(:template2) { create(:agent_template, category: 'research', featured: true) }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
      expect(assigns(:templates)).to match_array([ template1, template2 ])
    end

    it 'filters by category' do
      get :index, params: { category: 'coding' }
      expect(assigns(:templates)).to eq([ template1 ])
    end

    it 'filters featured' do
      get :index, params: { featured: 'true' }
      expect(assigns(:templates)).to eq([ template2 ])
    end

    context 'with skills and tools configured' do
      let!(:template_with_config) do
        create(:agent_template,
          category: 'coding',
          skills_config: { "enabled" => %w[github git] },
          tools_config: { "enabled" => %w[shell web_search file_read] }
        )
      end

      it 'renders the index page successfully' do
        get :index
        expect(response).to have_http_status(:ok)
        expect(assigns(:templates)).to include(template_with_config)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #show' do
    let(:template) { create(:agent_template) }

    it 'returns a successful response' do
      get :show, params: { id: template.id }
      expect(response).to be_successful
      expect(assigns(:template)).to eq(template)
    end
  end

  describe 'POST #deploy' do
    let(:template) { create(:agent_template) }
    let(:agent) { create(:agent) }

    context 'when successful' do
      it 'redirects to agent path' do
        result = double(success?: true, data: { agent: agent })
        allow_any_instance_of(AgentTemplate).to receive(:deploy).and_return(result)

        post :deploy, params: { id: template.id, name: 'My Agent' }
        expect(response).to redirect_to(agent_path(agent))
        expect(flash[:notice]).to include('deployed successfully')
      end
    end

    context 'when failed' do
      it 'redirects back with alert' do
        result = double(success?: false, error: 'Deploy failed')
        allow_any_instance_of(AgentTemplate).to receive(:deploy).and_return(result)

        post :deploy, params: { id: template.id, name: 'My Agent' }
        expect(response).to redirect_to(agent_template_path(template))
        expect(flash[:alert]).to eq('Deploy failed')
      end
    end

    context 'with team' do
      let(:team) { create(:team) }

      it 'passes team to deploy' do
        result = double(success?: true, data: { agent: agent })
        expect_any_instance_of(AgentTemplate).to receive(:deploy).with(name: 'My Agent', team: team).and_return(result)

        post :deploy, params: { id: template.id, name: 'My Agent', team_id: team.id }
      end
    end
  end
end
