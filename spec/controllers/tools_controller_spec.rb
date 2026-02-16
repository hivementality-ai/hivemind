# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ToolsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:tool) { create(:tool) }

  before do
    sign_in user
  end

  describe 'GET #index' do
    let!(:tool1) { create(:tool, name: "Beta Tool") }
    let!(:tool2) { create(:tool, name: "Alpha Tool") }
    let!(:execution1) { create(:tool_execution, tool: tool1, created_at: 1.hour.ago) }
    let!(:execution2) { create(:tool_execution, tool: tool2, created_at: 2.hours.ago) }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns @tools ordered by name' do
      get :index
      tools = assigns(:tools)
      expect(tools.map(&:name)).to eq([ "Alpha Tool", "Beta Tool" ])
    end

    it 'assigns @recent_executions ordered by created_at desc' do
      get :index
      executions = assigns(:recent_executions)
      expect(executions.first).to eq(execution1) # More recent first
      expect(executions.last).to eq(execution2)
    end

    it 'limits recent executions to 20' do
      25.times { create(:tool_execution) }
      get :index
      expect(assigns(:recent_executions).count).to eq(20)
    end

    it 'includes associations in recent executions' do
      get :index
      execution = assigns(:recent_executions).first
      expect(execution.association(:tool)).to be_loaded
      expect(execution.association(:agent)).to be_loaded
      expect(execution.association(:session)).to be_loaded
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
    let!(:execution1) { create(:tool_execution, tool: tool, created_at: 1.hour.ago) }
    let!(:execution2) { create(:tool_execution, tool: tool, created_at: 2.hours.ago) }
    let!(:other_tool_execution) { create(:tool_execution) }

    it 'returns a successful response' do
      get :show, params: { id: tool.id }
      expect(response).to be_successful
    end

    it 'assigns @tool' do
      get :show, params: { id: tool.id }
      expect(assigns(:tool)).to eq(tool)
    end

    it 'assigns @executions for the tool ordered by created_at desc' do
      get :show, params: { id: tool.id }
      executions = assigns(:executions)
      expect(executions).to include(execution1, execution2)
      expect(executions).not_to include(other_tool_execution)
      expect(executions.first).to eq(execution1) # More recent first
    end

    it 'limits executions to 50' do
      55.times { create(:tool_execution, tool: tool) }
      get :show, params: { id: tool.id }
      expect(assigns(:executions).count).to eq(50)
    end

    it 'includes associations in executions' do
      get :show, params: { id: tool.id }
      execution = assigns(:executions).first
      expect(execution.association(:agent)).to be_loaded
      expect(execution.association(:session)).to be_loaded
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :show, params: { id: tool.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #new' do
    it 'returns a successful response' do
      get :new
      expect(response).to be_successful
    end

    it 'assigns a new tool with default attributes' do
      get :new
      tool = assigns(:tool)
      expect(tool).to be_a_new(Tool)
      expect(tool.executor_type).to eq("custom_script")
      expect(tool.enabled).to be true
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
        tool: {
          name: "Test Tool",
          description: "A test tool",
          executor_type: "custom_script",
          enabled: true,
          requires_approval: false,
          script_template: "echo 'hello'"
        }
      }
    end

    context 'with valid params' do
      it 'creates a new tool' do
        expect {
          post :create, params: valid_params
        }.to change(Tool, :count).by(1)
      end

      it 'sets the correct attributes' do
        post :create, params: valid_params
        tool = Tool.last
        expect(tool.name).to eq("Test Tool")
        expect(tool.description).to eq("A test tool")
        expect(tool.executor_type).to eq("custom_script")
        expect(tool.enabled).to be true
        expect(tool.requires_approval).to be false
        expect(tool.script_template).to eq("echo 'hello'")
      end

      it 'redirects to tools index' do
        post :create, params: valid_params
        expect(response).to redirect_to(tools_path)
      end

      it 'sets a success notice' do
        post :create, params: valid_params
        expect(flash[:notice]).to eq("Tool created")
      end

      context 'with parameters schema JSON' do
        let(:schema_json) { '{"type": "object", "properties": {"param1": {"type": "string"}}}' }
        let(:params_with_schema) do
          valid_params.merge(
            tool: valid_params[:tool].merge(parameters_schema_json: schema_json)
          )
        end

        it 'parses and sets parameters schema' do
          post :create, params: params_with_schema
          tool = Tool.last
          expect(tool.parameters_schema).to eq({
            "type" => "object",
            "properties" => {
              "param1" => { "type" => "string" }
            }
          })
        end
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          tool: {
            name: "",
            description: ""
          }
        }
      end

      it 'does not create a tool' do
        expect {
          post :create, params: invalid_params
        }.not_to change(Tool, :count)
      end

      it 'renders new template' do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
      end

      it 'returns unprocessable entity status' do
        post :create, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with invalid JSON schema' do
      let(:params_with_invalid_schema) do
        valid_params.merge(
          tool: valid_params[:tool].merge(parameters_schema_json: 'invalid json')
        )
      end

      it 'still creates the tool (JSON schema is optional)' do
        expect {
          post :create, params: params_with_invalid_schema
        }.to change(Tool, :count).by(1)
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
      get :edit, params: { id: tool.id }
      expect(response).to be_successful
    end

    it 'assigns @tool' do
      get :edit, params: { id: tool.id }
      expect(assigns(:tool)).to eq(tool)
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :edit, params: { id: tool.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'PATCH #update' do
    let(:new_attributes) do
      {
        name: "Updated Tool",
        description: "Updated description",
        enabled: false
      }
    end

    context 'with valid params' do
      it 'updates the tool' do
        patch :update, params: { id: tool.id, tool: new_attributes }
        tool.reload
        expect(tool.name).to eq("Updated Tool")
        expect(tool.description).to eq("Updated description")
        expect(tool.enabled).to be false
      end

      it 'redirects to tools index' do
        patch :update, params: { id: tool.id, tool: new_attributes }
        expect(response).to redirect_to(tools_path)
      end

      it 'sets a success notice' do
        patch :update, params: { id: tool.id, tool: new_attributes }
        expect(flash[:notice]).to eq("Tool updated")
      end

      context 'with parameters schema JSON' do
        let(:schema_json) { '{"type": "object", "properties": {"param1": {"type": "string"}}}' }
        let(:params_with_schema) do
          { id: tool.id, tool: new_attributes.merge(parameters_schema_json: schema_json) }
        end

        it 'parses and updates parameters schema' do
          patch :update, params: params_with_schema
          tool.reload
          expect(tool.parameters_schema).to eq({
            "type" => "object",
            "properties" => {
              "param1" => { "type" => "string" }
            }
          })
        end
      end
    end

    context 'with invalid params' do
      let(:invalid_attributes) do
        {
          name: "",
          description: ""
        }
      end

      it 'does not update the tool' do
        original_name = tool.name
        patch :update, params: { id: tool.id, tool: invalid_attributes }
        tool.reload
        expect(tool.name).to eq(original_name)
      end

      it 'renders edit template' do
        patch :update, params: { id: tool.id, tool: invalid_attributes }
        expect(response).to render_template(:edit)
      end

      it 'returns unprocessable entity status' do
        patch :update, params: { id: tool.id, tool: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with invalid JSON schema' do
      let(:params_with_invalid_schema) do
        { id: tool.id, tool: new_attributes.merge(parameters_schema_json: 'invalid json') }
      end

      it 'still updates the tool (JSON schema is optional)' do
        patch :update, params: params_with_invalid_schema
        tool.reload
        expect(tool.name).to eq("Updated Tool")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        patch :update, params: { id: tool.id, tool: new_attributes }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:tool_to_delete) { create(:tool) }

    it 'destroys the tool' do
      expect {
        delete :destroy, params: { id: tool_to_delete.id }
      }.to change(Tool, :count).by(-1)
    end

    it 'redirects to tools index' do
      delete :destroy, params: { id: tool_to_delete.id }
      expect(response).to redirect_to(tools_path)
    end

    it 'sets a success notice' do
      delete :destroy, params: { id: tool_to_delete.id }
      expect(flash[:notice]).to eq("Tool deleted")
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        delete :destroy, params: { id: tool_to_delete.id }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
