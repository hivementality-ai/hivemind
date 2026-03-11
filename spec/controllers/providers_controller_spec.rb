# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProvidersController, type: :controller do
  let(:owner) { create(:user, :owner) }
  let(:admin) { create(:user, :admin) }
  let(:operator) { create(:user, :operator) }
  let(:viewer) { create(:user, :viewer) }

  let(:anthropic_provider) do
    create(:provider_config, name: 'Anthropic', adapter_type: 'anthropic')
  end

  let(:openai_provider) do
    create(:provider_config, name: 'OpenAI', adapter_type: 'openai')
  end

  describe 'Authorization' do
    let!(:auth_provider) do
      create(:provider_config, name: 'Test Provider', adapter_type: 'anthropic')
    end

    context 'when not authenticated' do
      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when viewer is signed in' do
      before { sign_in viewer }

      it 'redirects to root for index' do
        get :index
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Access denied.')
      end

      it 'redirects to root for show' do
        get :show, params: { id: auth_provider.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Access denied.')
      end
    end

    context 'when operator is signed in' do
      before { sign_in operator }

      it 'redirects to root for edit' do
        get :edit, params: { id: auth_provider.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Access denied.')
      end
    end

    context 'when admin is signed in' do
      before { sign_in admin }

      it 'allows access to index' do
        get :index
        expect(response).to be_successful
      end

      it 'allows access to show' do
        get :show, params: { id: auth_provider.id }
        expect(response).to be_successful
      end

      it 'allows access to edit' do
        get :edit, params: { id: auth_provider.id }
        expect(response).to be_successful
      end
    end

    context 'when owner is signed in' do
      before { sign_in owner }

      it 'allows access to index' do
        get :index
        expect(response).to be_successful
      end

      it 'allows access to show' do
        get :show, params: { id: auth_provider.id }
        expect(response).to be_successful
      end

      it 'allows access to edit' do
        get :edit, params: { id: auth_provider.id }
        expect(response).to be_successful
      end
    end
  end

  describe 'GET #index' do
    before { sign_in owner }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns all providers' do
      create_list(:provider_config, 3)
      get :index
      expect(assigns(:providers).count).to eq(3)
    end

    it 'orders providers by name' do
      create(:provider_config, name: 'Zebra', adapter_type: 'ollama')
      create(:provider_config, name: 'Apple', adapter_type: 'openai')
      get :index
      expect(assigns(:providers).map(&:name)).to eq([ 'Apple', 'Zebra' ])
    end
  end

  describe 'GET #show' do
    before { sign_in owner }

    it 'returns a successful response' do
      get :show, params: { id: anthropic_provider.id }
      expect(response).to be_successful
    end

    it 'assigns the requested provider' do
      get :show, params: { id: anthropic_provider.id }
      expect(assigns(:provider)).to eq(anthropic_provider)
    end
  end

  describe 'GET #edit' do
    before { sign_in owner }

    context 'for Anthropic provider' do
      it 'returns a successful response' do
        get :edit, params: { id: anthropic_provider.id }
        expect(response).to be_successful
      end

      it 'assigns available models' do
        get :edit, params: { id: anthropic_provider.id }
        available = assigns(:available_models)
        expect(available.map { |m| m[:id] }).to include('claude-opus-4-6', 'claude-sonnet-4-5', 'claude-haiku-4-5')
      end
    end

    context 'for OpenAI provider' do
      it 'assigns OpenAI models' do
        get :edit, params: { id: openai_provider.id }
        available = assigns(:available_models)
        expect(available.map { |m| m[:id] }).to include('gpt-5.2', 'gpt-5.2-mini', 'o3')
      end
    end

    context 'for Ollama provider' do
      let(:ollama_provider) do
        create(:provider_config, name: 'Ollama', adapter_type: 'ollama')
      end

      it 'assigns empty models for Ollama' do
        get :edit, params: { id: ollama_provider.id }
        expect(assigns(:available_models)).to be_empty
      end
    end
  end

  describe 'PATCH/PUT #update' do
    before { sign_in owner }

    let(:anthropic_provider) do
      create(:provider_config,
        name: 'Anthropic',
        adapter_type: 'anthropic',
        model_definitions: [])
    end

    context 'with valid params' do
      it 'updates the provider and stores API key' do
        patch :update, params: {
          id: anthropic_provider.id,
          provider_config: {
            api_key: 'sk-ant-test-key-123',
            models: [ 'claude-sonnet-4-5', 'claude-haiku-4-5' ],
            default_model: 'claude-sonnet-4-5'
          }
        }

        anthropic_provider.reload
        expect(anthropic_provider.model_definitions.count).to eq(2)
        expect(anthropic_provider.model_definitions.find { |m| m['default'] }['id']).to eq('claude-sonnet-4-5')

        namespace, key = anthropic_provider.vault_key.split("/", 2)
        vault_entry = VaultEntry.find_by(namespace:, key:)
        expect(vault_entry.encrypted_value).to eq('sk-ant-test-key-123')
      end

      it 'redirects to index on success' do
        patch :update, params: {
          id: anthropic_provider.id,
          provider_config: {
            api_key: 'sk-ant-test-key',
            models: [ 'claude-sonnet-4-5' ],
            default_model: 'claude-sonnet-4-5'
          }
        }
        expect(response).to redirect_to(provider_path(anthropic_provider))
        expect(flash[:notice]).to include('Provider updated successfully')
      end

      it 'saves default model to settings' do
        patch :update, params: {
          id: anthropic_provider.id,
          provider_config: {
            api_key: 'sk-ant-test-key',
            models: [ 'claude-sonnet-4-5' ],
            default_model: 'claude-opus-4-6'
          }
        }

        expect(Setting.get('default_model_anthropic')).to eq('claude-opus-4-6')
      end

      it 'updates without changing API key if not provided' do
        # Set initial key
        VaultEntry.find_or_initialize_by(
          namespace: 'providers',
          key: 'anthropic_api_key'
        ).tap do |ve|
          ve.encrypted_value = 'original-key'
          ve.save!
        end

        patch :update, params: {
          id: anthropic_provider.id,
          provider_config: {
            api_key: '',
            models: [ 'claude-haiku-4-5' ],
            default_model: 'claude-haiku-4-5'
          }
        }

        vault_entry = VaultEntry.find_by(
          namespace: 'providers',
          key: 'anthropic_api_key'
        )
        expect(vault_entry.encrypted_value).to eq('original-key')
      end
    end

    context 'with invalid params' do
      it 'renders edit template on failure' do
        # Create an invalid scenario - e.g., update fails on save
        allow_any_instance_of(ProviderConfig).to receive(:save).and_return(false)

        patch :update, params: {
          id: anthropic_provider.id,
          provider_config: {
            api_key: 'invalid',
            models: []
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:edit_form)
      end
    end
  end

  describe 'GET #new' do
    before { sign_in owner }

    it 'returns a successful response' do
      get :new
      expect(response).to be_successful
    end

    it 'assigns all adapter types regardless of existing providers' do
      create(:provider_config, name: 'Anthropic', adapter_type: 'anthropic')
      get :new
      expect(assigns(:available_types)).to include('anthropic', 'openai', 'ollama', 'llama_cpp')
    end
  end

  describe 'POST #create' do
    before { sign_in owner }

    context 'with valid params' do
      it 'creates a new provider and redirects to show' do
        expect {
          post :create, params: {
            provider_config: {
              adapter_type: 'anthropic',
              api_key: 'sk-ant-test-key',
              models: [ 'claude-sonnet-4-5', 'claude-haiku-4-5' ],
              default_model: 'claude-sonnet-4-5'
            }
          }
        }.to change(ProviderConfig, :count).by(1)

        provider = ProviderConfig.last
        expect(provider.name).to eq('Anthropic')
        expect(provider.adapter_type).to eq('anthropic')
        expect(provider.vault_key).to eq('providers/anthropic_api_key')
        expect(provider.model_definitions.count).to eq(2)
        expect(response).to redirect_to(provider_path(provider))
        expect(flash[:notice]).to include('Provider added successfully')
      end

      it 'stores the API key in the vault' do
        post :create, params: {
          provider_config: {
            adapter_type: 'openai',
            api_key: 'sk-test-key-123',
            models: [ 'gpt-5.2' ],
            default_model: 'gpt-5.2'
          }
        }

        vault_entry = VaultEntry.find_by(namespace: 'providers', key: 'openai_api_key')
        expect(vault_entry.encrypted_value).to eq('sk-test-key-123')
      end

      it 'saves default model to settings' do
        post :create, params: {
          provider_config: {
            adapter_type: 'anthropic',
            api_key: 'sk-ant-test',
            models: [ 'claude-sonnet-4-5' ],
            default_model: 'claude-sonnet-4-5'
          }
        }

        expect(Setting.get('default_model_anthropic')).to eq('claude-sonnet-4-5')
      end

      it 'creates provider without API key for local providers' do
        post :create, params: {
          provider_config: {
            adapter_type: 'ollama',
            api_key: '',
            models: [ 'llama3.2:3b' ],
            default_model: 'llama3.2:3b'
          }
        }

        provider = ProviderConfig.last
        expect(provider.adapter_type).to eq('ollama')
        expect(response).to redirect_to(provider_path(provider))
      end
    end

    context 'with duplicate adapter_type' do
      it 'allows a second provider of the same type with a different name' do
        create(:provider_config, name: 'Anthropic', adapter_type: 'anthropic')

        expect {
          post :create, params: {
            provider_config: {
              adapter_type: 'anthropic',
              name: 'Anthropic EU',
              api_key: 'sk-ant-second',
              models: [ 'claude-sonnet-4-5' ],
              default_model: 'claude-sonnet-4-5'
            }
          }
        }.to change(ProviderConfig, :count).by(1)

        provider = ProviderConfig.last
        expect(provider.name).to eq('Anthropic EU')
        expect(provider.adapter_type).to eq('anthropic')
      end

      it 'rejects duplicate names' do
        create(:provider_config, name: 'Openai', adapter_type: 'openai')

        expect {
          post :create, params: {
            provider_config: {
              adapter_type: 'openai',
              name: 'Openai',
              api_key: 'sk-dup',
              models: [ 'gpt-5.2' ],
              default_model: 'gpt-5.2'
            }
          }
        }.not_to change(ProviderConfig, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'Provider param filtering' do
    before { sign_in owner }

    it 'allows api_key, default_model, and models' do
      patch :update, params: {
        id: anthropic_provider.id,
        provider_config: {
          api_key: 'sk-test',
          default_model: 'claude-sonnet-4-5',
          models: [ 'claude-sonnet-4-5' ]
        }
      }
      expect(response).to redirect_to(provider_path(anthropic_provider))
    end

    it 'prevents mass assignment of other attributes' do
      patch :update, params: {
        id: anthropic_provider.id,
        provider_config: {
          api_key: 'sk-test',
          name: 'Hacked Provider',
          adapter_type: 'malicious',
          models: []
        }
      }
      anthropic_provider.reload
      expect(anthropic_provider.name).to eq('Anthropic')
      expect(anthropic_provider.adapter_type).to eq('anthropic')
    end
  end
end
