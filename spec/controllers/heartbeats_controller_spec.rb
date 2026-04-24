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

    it 'assigns @heartbeat_memory from system assistant memories' do
      soul = create(:agent, name: 'Assistant', system_agent: true, role: 'General Assistant', enabled: true)
      mem = create(:memory_entry, agent: soul, content: 'Latest heartbeat summary')

      get :index

      expect(assigns(:heartbeat_memory)).to eq(mem)
    end

    it 'assigns nil @heartbeat_memory when no memories exist' do
      create(:agent, name: 'Assistant', system_agent: true, role: 'General Assistant', enabled: true)

      get :index

      expect(assigns(:heartbeat_memory)).to be_nil
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

  describe 'PATCH #update_soul' do
    let!(:soul_agent) { create(:agent, name: 'Assistant', system_agent: true, role: 'General Assistant', enabled: true) }

    it 'updates the system prompt and redirects' do
      patch :update_soul, params: { system_prompt: 'You are a diligent monitor.' }
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:notice]).to include('Soul updated')
      expect(soul_agent.reload.system_prompt).to eq('You are a diligent monitor.')
    end

    it 'strips leading/trailing whitespace from the prompt' do
      patch :update_soul, params: { system_prompt: '   trimmed   ' }
      expect(soul_agent.reload.system_prompt).to eq('trimmed')
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        patch :update_soul, params: { system_prompt: 'anything' }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE #clear_memories' do
    let!(:soul_agent) { create(:agent, name: 'Assistant', system_agent: true, role: 'General Assistant', enabled: true) }

    it 'deletes all memory entries for the system assistant and redirects' do
      create(:memory_entry, agent: soul_agent, content: 'old memory 1')
      create(:memory_entry, agent: soul_agent, content: 'old memory 2')

      expect { delete :clear_memories }.to change { soul_agent.memory_entries.count }.from(2).to(0)
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:notice]).to include('Cleared 2')
    end

    it 'handles the case when no memories exist' do
      delete :clear_memories
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:notice]).to include('Cleared 0')
    end

    it 'does not delete memories belonging to other agents' do
      other_agent = create(:agent, name: 'Other Agent')
      create(:memory_entry, agent: other_agent, content: 'should survive')
      create(:memory_entry, agent: soul_agent, content: 'should be deleted')

      delete :clear_memories

      expect(other_agent.memory_entries.count).to eq(1)
      expect(soul_agent.memory_entries.count).to eq(0)
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        delete :clear_memories
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE #delete_standing_task' do
    before do
      standing = [
        { 'task' => 'Check logs', 'protected' => true, 'added_by' => 'user', 'added_at' => Time.current.iso8601 },
        { 'task' => 'Temp task',  'protected' => false, 'added_by' => 'agent', 'added_at' => Time.current.iso8601 }
      ]
      Setting.set('heartbeat_tasks', standing.to_json)
    end

    it 'deletes an existing standing item and redirects with notice' do
      delete :delete_standing_task, params: { task: 'Check logs' }
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:notice]).to include('deleted')

      tasks = JSON.parse(Setting.get('heartbeat_tasks'))
      expect(tasks.none? { |t| t['task'] == 'Check logs' }).to be true
    end

    it 'does not delete a temporary (non-protected) task' do
      delete :delete_standing_task, params: { task: 'Temp task' }
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:alert]).to include('not found')

      tasks = JSON.parse(Setting.get('heartbeat_tasks'))
      expect(tasks.any? { |t| t['task'] == 'Temp task' }).to be true
    end

    it 'returns an alert when the task does not exist' do
      delete :delete_standing_task, params: { task: 'Nonexistent task' }
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:alert]).to include('not found')
    end

    it 'returns an alert when no task param is given' do
      delete :delete_standing_task, params: { task: '' }
      expect(response).to redirect_to(heartbeats_path)
      expect(flash[:alert]).to be_present
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        delete :delete_standing_task, params: { task: 'Check logs' }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
