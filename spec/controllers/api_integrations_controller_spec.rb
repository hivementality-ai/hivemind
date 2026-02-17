# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiIntegrationsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:integration) { create(:api_integration) }

  before { sign_in user }

  describe 'GET #index' do
    let!(:integration) { create(:api_integration) }

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
      expect(assigns(:integrations)).to eq([ integration ])
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #new' do
    it 'returns a successful response' do
      get :new
      expect(response).to be_successful
    end
  end

  describe 'POST #create' do
    context 'without spec parsing' do
      it 'creates an integration' do
        expect {
          post :create, params: { api_integration: { name: 'Test API', base_url: 'https://api.test.com' } }
        }.to change(ApiIntegration, :count).by(1)
        expect(response).to redirect_to(api_integration_path(ApiIntegration.last))
      end
    end

    context 'with spec text' do
      it 'parses spec and creates integration' do
        result = double(success?: true, data: {
          title: 'Parsed API', base_url: 'https://parsed.com', description: 'Desc',
          spec_format: 'openapi', spec_data: {}, endpoints: [ { path: '/test' } ]
        })
        allow(ApiIntegrations::SpecParser).to receive(:call).and_return(result)

        post :create, params: {
          spec_text: '{"openapi": "3.0"}',
          api_integration: { name: 'My API', base_url: '' }
        }
        expect(response).to redirect_to(api_integration_path(ApiIntegration.last))
      end

      it 'redirects on parse failure' do
        result = double(success?: false, error: 'Invalid spec')
        allow(ApiIntegrations::SpecParser).to receive(:call).and_return(result)

        post :create, params: {
          spec_text: 'bad',
          api_integration: { name: 'Test', base_url: 'https://test.com' }
        }
        expect(response).to redirect_to(new_api_integration_path)
      end
    end

    it 'stores api key in vault' do
      post :create, params: {
        api_integration: { name: 'Test API', base_url: 'https://api.test.com' },
        api_key: 'secret_key',
        auth_type: 'bearer'
      }
      expect(VaultEntry.find_by(namespace: 'api_integrations')).to be_present
    end
  end

  describe 'GET #show' do
    it 'returns a successful response' do
      get :show, params: { id: integration.id }
      expect(response).to be_successful
    end
  end

  describe 'GET #edit' do
    it 'returns a successful response' do
      get :edit, params: { id: integration.id }
      expect(response).to be_successful
    end
  end

  describe 'PATCH #update' do
    it 'updates and redirects' do
      patch :update, params: { id: integration.id, api_integration: { name: 'Updated' } }
      expect(response).to redirect_to(api_integration_path(integration))
      expect(integration.reload.name).to eq('Updated')
    end

    context 'with invalid params' do
      it 'renders edit' do
        allow_any_instance_of(ApiIntegration).to receive(:save).and_return(false)
        patch :update, params: { id: integration.id, api_integration: { name: '' } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:integration) { create(:api_integration, auth_config: { 'vault_key' => 'test_key' }) }

    it 'destroys and cleans vault' do
      VaultEntry.create!(namespace: 'api_integrations', key: 'test_key', encrypted_value: 'val')
      expect {
        delete :destroy, params: { id: integration.id }
      }.to change(ApiIntegration, :count).by(-1)
      expect(VaultEntry.find_by(namespace: 'api_integrations', key: 'test_key')).to be_nil
      expect(response).to redirect_to(api_integrations_path)
    end
  end

  describe 'POST #test' do
    context 'when connection succeeds' do
      it 'returns ok' do
        http = double('http')
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_return(double(code: '200'))
        allow_any_instance_of(ApiIntegration).to receive(:request_headers).and_return({})

        post :test, params: { id: integration.id }
        expect(response.parsed_body['status']).to eq('ok')
      end
    end

    context 'when connection fails' do
      it 'returns error' do
        allow(Net::HTTP).to receive(:new).and_raise(StandardError, 'Connection refused')

        post :test, params: { id: integration.id }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['status']).to eq('error')
      end
    end
  end

  describe 'POST #import' do
    context 'with valid URL' do
      it 'imports spec from URL' do
        http_response = double(is_a?: true, body: '{"openapi":"3.0"}')
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
        allow(Net::HTTP).to receive(:get_response).and_return(http_response)

        result = double(success?: true, data: {
          title: 'Imported', base_url: 'https://imported.com', description: 'Desc',
          spec_format: 'openapi', spec_data: {}, endpoints: []
        })
        allow(ApiIntegrations::SpecParser).to receive(:call).and_return(result)

        post :import, params: { spec_url: 'https://example.com/spec.json' }
        expect(response).to redirect_to(api_integration_path(ApiIntegration.last))
      end
    end

    context 'with blank URL' do
      it 'redirects with alert' do
        post :import, params: { spec_url: '' }
        expect(response).to redirect_to(new_api_integration_path)
      end
    end

    context 'when fetch fails' do
      it 'redirects with alert' do
        http_response = double(is_a?: false, code: '404')
        allow(http_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(Net::HTTP).to receive(:get_response).and_return(http_response)

        post :import, params: { spec_url: 'https://example.com/bad' }
        expect(response).to redirect_to(new_api_integration_path)
      end
    end
  end
end
