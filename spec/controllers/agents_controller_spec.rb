# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AgentsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent) }

  before do
    sign_in user
  end

  describe 'GET #index' do
    let!(:agent1) { create(:agent, name: "Agent 1") }
    let!(:agent2) { create(:agent, name: "Agent 2") }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns @agents' do
      get :index
      expect(assigns(:agents)).to match_array([ agent1, agent2 ])
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
    it 'returns a successful response' do
      get :show, params: { slug: agent.slug }
      expect(response).to be_successful
    end

    it 'assigns @agent' do
      get :show, params: { slug: agent.slug }
      expect(assigns(:agent)).to eq(agent)
    end

    it 'assigns @recent_sessions' do
      create(:session, agent: agent)
      get :show, params: { slug: agent.slug }
      expect(assigns(:recent_sessions)).to be_present
    end

    it 'assigns @usage_today' do
      get :show, params: { slug: agent.slug }
      expect(assigns(:usage_today)).to be_a(Hash)
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :show, params: { slug: agent.slug }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #new' do
    it 'returns a successful response' do
      get :new
      expect(response).to be_successful
    end

    it 'assigns a new agent' do
      get :new
      expect(assigns(:agent)).to be_a_new(Agent)
    end

    it 'assigns @teams' do
      team = create(:team)
      get :new
      expect(assigns(:teams)).to include(team)
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :new
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        agent: {
          name: "New Agent",
          role: "Assistant",
          system_prompt: "You are helpful"
        }
      }
    end

    context 'with valid params' do
      it 'creates a new agent' do
        expect {
          post :create, params: valid_params
        }.to change(Agent, :count).by(1)
      end

      it 'redirects to the agent' do
        post :create, params: valid_params
        expect(response).to redirect_to(Agent.last)
      end

      it 'sets a success notice' do
        post :create, params: valid_params
        expect(flash[:notice]).to eq("Agent created successfully")
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          agent: {
            name: "",
            role: ""
          }
        }
      end

      it 'does not create an agent' do
        expect {
          post :create, params: invalid_params
        }.not_to change(Agent, :count)
      end

      it 'renders new template' do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
      end

      it 'returns unprocessable entity status' do
        post :create, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'assigns @teams' do
        team = create(:team)
        post :create, params: invalid_params
        expect(assigns(:teams)).to include(team)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :create, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #edit' do
    it 'returns a successful response' do
      get :edit, params: { slug: agent.slug }
      expect(response).to be_successful
    end

    it 'assigns @agent' do
      get :edit, params: { slug: agent.slug }
      expect(assigns(:agent)).to eq(agent)
    end

    it 'assigns @teams' do
      team = create(:team)
      get :edit, params: { slug: agent.slug }
      expect(assigns(:teams)).to include(team)
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :edit, params: { slug: agent.slug }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'PATCH #update' do
    let(:new_attributes) do
      {
        name: "Updated Agent",
        role: "Updated Role"
      }
    end

    context 'with valid params' do
      it 'updates the agent' do
        patch :update, params: { slug: agent.slug, agent: new_attributes }
        agent.reload
        expect(agent.name).to eq("Updated Agent")
        expect(agent.role).to eq("Updated Role")
      end

      it 'redirects to the agent' do
        patch :update, params: { slug: agent.slug, agent: new_attributes }
        expect(response).to redirect_to(agent)
      end

      it 'sets a success notice' do
        patch :update, params: { slug: agent.slug, agent: new_attributes }
        expect(flash[:notice]).to eq("Agent updated successfully")
      end
    end

    context 'with invalid params' do
      let(:invalid_attributes) do
        {
          name: "",
          role: ""
        }
      end

      it 'does not update the agent' do
        original_name = agent.name
        patch :update, params: { slug: agent.slug, agent: invalid_attributes }
        agent.reload
        expect(agent.name).to eq(original_name)
      end

      it 'renders edit template' do
        patch :update, params: { slug: agent.slug, agent: invalid_attributes }
        expect(response).to render_template(:edit)
      end

      it 'returns unprocessable entity status' do
        patch :update, params: { slug: agent.slug, agent: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'assigns @teams' do
        team = create(:team)
        patch :update, params: { slug: agent.slug, agent: invalid_attributes }
        expect(assigns(:teams)).to include(team)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        patch :update, params: { slug: agent.slug, agent: new_attributes }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:agent_to_delete) { create(:agent) }

    it 'destroys the agent' do
      expect {
        delete :destroy, params: { slug: agent_to_delete.slug }
      }.to change(Agent, :count).by(-1)
    end

    it 'redirects to agents list' do
      delete :destroy, params: { slug: agent_to_delete.slug }
      expect(response).to redirect_to(agents_url)
    end

    it 'sets a success notice' do
      delete :destroy, params: { slug: agent_to_delete.slug }
      expect(flash[:notice]).to eq("Agent deleted successfully")
    end

    it 'destroys the agent and its sessions and tool_executions' do
      session = create(:session, agent: agent_to_delete)
      create(:tool_execution, session: session, agent: agent_to_delete)

      expect {
        delete :destroy, params: { slug: agent_to_delete.slug }
      }.to change(Agent, :count).by(-1)
        .and change(Session, :count).by(-1)
        .and change(ToolExecution, :count).by(-1)
    end

    context 'when a foreign key violation occurs' do
      before do
        allow_any_instance_of(Agent).to receive(:destroy).and_raise(
          ActiveRecord::InvalidForeignKey.new("FK violation")
        )
      end

      it 'redirects back to the agent with an alert' do
        delete :destroy, params: { slug: agent_to_delete.slug }
        expect(response).to redirect_to(agent_to_delete)
      end

      it 'sets an alert message' do
        delete :destroy, params: { slug: agent_to_delete.slug }
        expect(flash[:alert]).to match(/Unable to delete agent/)
      end

      it 'does not destroy the agent' do
        expect {
          delete :destroy, params: { slug: agent_to_delete.slug }
        }.not_to change(Agent, :count)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        delete :destroy, params: { slug: agent_to_delete.slug }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
