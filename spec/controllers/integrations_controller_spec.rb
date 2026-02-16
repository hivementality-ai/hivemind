# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
  end

  describe 'GET #index' do
    let!(:github_vault) { create(:vault_entry, namespace: "github", key: "token", value: "test_token") }
    let!(:gmail_vault) { create(:vault_entry, namespace: "google", key: "gmail_address", value: "test@gmail.com") }

    before do
      allow(CloudStorage::ConfigureRemote).to receive(:list_remotes).and_return([])
    end

    it 'returns a successful response' do
      get :index
      expect(response).to be_successful
    end

    it 'assigns integration status variables' do
      get :index
      expect(assigns(:github_configured)).to be true
      expect(assigns(:gmail_configured)).to be true
      expect(assigns(:email_configured)).to be false
      expect(assigns(:jira_configured)).to be false
    end

    it 'assigns cloud storage data' do
      get :index
      expect(assigns(:remotes)).to eq([])
      expect(assigns(:backends)).to be_present
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :index
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #update_github' do
    context 'with valid token' do
      let(:token) { "ghp_1234567890abcdef" }

      before do
        allow(controller).to receive(:configure_github_cli)
      end

      it 'stores the token in vault' do
        expect {
          post :update_github, params: { github_token: token }
        }.to change(VaultEntry, :count).by(1)

        entry = VaultEntry.find_by(namespace: "github", key: "token")
        expect(entry.value).to eq(token)
      end

      it 'configures GitHub CLI' do
        expect(controller).to receive(:configure_github_cli).with(token)
        post :update_github, params: { github_token: token }
      end

      it 'redirects with success notice' do
        post :update_github, params: { github_token: token }
        expect(response).to redirect_to(integrations_path)
        expect(flash[:notice]).to include("GitHub connected")
      end
    end

    context 'with blank token' do
      it 'redirects with error' do
        post :update_github, params: { github_token: "   " }
        expect(response).to redirect_to(integrations_path)
        expect(flash[:alert]).to eq("Personal access token required")
      end

      it 'does not create vault entry' do
        expect {
          post :update_github, params: { github_token: "" }
        }.not_to change(VaultEntry, :count)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :update_github, params: { github_token: "test_token" }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #test_github' do
    context 'when GitHub is configured' do
      let!(:github_vault) { create(:vault_entry, namespace: "github", key: "token", value: "valid_token") }

      before do
        stub_request(:get, "https://api.github.com/user")
          .with(headers: { 'Authorization' => 'Bearer valid_token' })
          .to_return(
            status: 200,
            body: { login: 'testuser', name: 'Test User' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success response' do
        get :test_github
        expect(response).to be_successful
        json = JSON.parse(response.body)
        expect(json['status']).to eq('connected')
        expect(json['user']).to eq('testuser')
        expect(json['name']).to eq('Test User')
      end
    end

    context 'when GitHub is not configured' do
      it 'returns error response' do
        get :test_github
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('error')
        expect(json['message']).to eq('GitHub not configured')
      end
    end

    context 'when API returns error' do
      let!(:github_vault) { create(:vault_entry, namespace: "github", key: "token", value: "invalid_token") }

      before do
        stub_request(:get, "https://api.github.com/user")
          .with(headers: { 'Authorization' => 'Bearer invalid_token' })
          .to_return(status: 401, body: 'Unauthorized')
      end

      it 'returns error response' do
        get :test_github
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('error')
        expect(json['message']).to eq('HTTP 401')
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :test_github
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #update_gmail' do
    context 'with valid credentials' do
      let(:email) { "test@gmail.com" }
      let(:password) { "app_password_123" }

      it 'stores the credentials in vault' do
        expect {
          post :update_gmail, params: { gmail_address: email, gmail_app_password: password }
        }.to change(VaultEntry, :count).by(2)

        expect(VaultEntry.find_by(namespace: "google", key: "gmail_address").value).to eq(email)
        expect(VaultEntry.find_by(namespace: "google", key: "gmail_app_password").value).to eq(password)
      end

      it 'redirects with success notice' do
        post :update_gmail, params: { gmail_address: email, gmail_app_password: password }
        expect(response).to redirect_to(integrations_path)
        expect(flash[:notice]).to eq("Gmail credentials saved")
      end
    end

    context 'with missing credentials' do
      it 'redirects with error when email missing' do
        post :update_gmail, params: { gmail_address: "", gmail_app_password: "password" }
        expect(response).to redirect_to(integrations_path)
        expect(flash[:alert]).to eq("Email and app password required")
      end

      it 'redirects with error when password missing' do
        post :update_gmail, params: { gmail_address: "test@gmail.com", gmail_app_password: "" }
        expect(response).to redirect_to(integrations_path)
        expect(flash[:alert]).to eq("Email and app password required")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :update_gmail, params: { gmail_address: "test@gmail.com", gmail_app_password: "password" }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #update_email' do
    let(:valid_params) do
      {
        smtp_host: "smtp.example.com",
        smtp_port: "587",
        smtp_username: "user@example.com",
        smtp_password: "password123",
        from_address: "noreply@example.com",
        from_name: "Test Service"
      }
    end

    context 'with valid SMTP settings' do
      it 'stores all settings in vault' do
        expect {
          post :update_email, params: valid_params
        }.to change(VaultEntry, :count).by(6)

        expect(VaultEntry.find_by(namespace: "email", key: "smtp_host").value).to eq("smtp.example.com")
        expect(VaultEntry.find_by(namespace: "email", key: "smtp_port").value).to eq("587")
        expect(VaultEntry.find_by(namespace: "email", key: "smtp_username").value).to eq("user@example.com")
        expect(VaultEntry.find_by(namespace: "email", key: "smtp_password").value).to eq("password123")
        expect(VaultEntry.find_by(namespace: "email", key: "from_address").value).to eq("noreply@example.com")
        expect(VaultEntry.find_by(namespace: "email", key: "from_name").value).to eq("Test Service")
      end

      it 'uses default port when not specified' do
        post :update_email, params: valid_params.except(:smtp_port)
        expect(VaultEntry.find_by(namespace: "email", key: "smtp_port").value).to eq("587")
      end

      it 'redirects with success notice' do
        post :update_email, params: valid_params
        expect(response).to redirect_to(integrations_path)
        expect(flash[:notice]).to eq("SMTP credentials saved")
      end
    end

    context 'with missing required fields' do
      it 'redirects with error when host missing' do
        post :update_email, params: valid_params.merge(smtp_host: "")
        expect(response).to redirect_to(integrations_path)
        expect(flash[:alert]).to eq("Host, username, and password are required")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :update_email, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #update_jira' do
    let(:valid_params) do
      {
        jira_base_url: "https://company.atlassian.net/",
        jira_email: "user@company.com",
        jira_api_token: "api_token_123"
      }
    end

    context 'with valid Jira settings' do
      it 'stores settings in vault and strips trailing slash from URL' do
        expect {
          post :update_jira, params: valid_params
        }.to change(VaultEntry, :count).by(3)

        expect(VaultEntry.find_by(namespace: "jira", key: "base_url").value).to eq("https://company.atlassian.net")
        expect(VaultEntry.find_by(namespace: "jira", key: "email").value).to eq("user@company.com")
        expect(VaultEntry.find_by(namespace: "jira", key: "api_token").value).to eq("api_token_123")
      end

      it 'redirects with success notice' do
        post :update_jira, params: valid_params
        expect(response).to redirect_to(integrations_path)
        expect(flash[:notice]).to eq("Jira credentials saved")
      end
    end

    context 'with missing required fields' do
      it 'redirects with error when any field is missing' do
        post :update_jira, params: valid_params.merge(jira_email: "")
        expect(response).to redirect_to(integrations_path)
        expect(flash[:alert]).to eq("All three Jira fields are required")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :update_jira, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #test_jira' do
    context 'when Jira is configured' do
      before do
        create(:vault_entry, namespace: "jira", key: "base_url", value: "https://company.atlassian.net")
        create(:vault_entry, namespace: "jira", key: "email", value: "user@company.com")
        create(:vault_entry, namespace: "jira", key: "api_token", value: "valid_token")

        stub_request(:get, "https://company.atlassian.net/rest/api/3/myself")
          .to_return(
            status: 200,
            body: { displayName: 'Test User', emailAddress: 'user@company.com' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success response' do
        get :test_jira
        expect(response).to be_successful
        json = JSON.parse(response.body)
        expect(json['status']).to eq('connected')
        expect(json['user']).to eq('Test User')
        expect(json['email']).to eq('user@company.com')
      end
    end

    context 'when Jira is not configured' do
      it 'returns error response' do
        get :test_jira
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('error')
        expect(json['message']).to eq('Jira not configured')
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :test_jira
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'POST #add_cloud_remote' do
    let(:valid_params) do
      {
        backend: "s3",
        remote_name: "test_remote",
        token: "access_token",
        access_key_id: "AKIA123456789",
        secret_access_key: "secret_key",
        region: "us-west-2"
      }
    end

    before do
      allow(CloudStorage::ConfigureRemote).to receive(:new).and_return(
        double(call: { success: true })
      )
    end

    context 'with valid parameters' do
      it 'calls ConfigureRemote service' do
        expect(CloudStorage::ConfigureRemote).to receive(:new).with(
          backend: "s3",
          remote_name: "test_remote",
          token: "access_token",
          params: {
            access_key_id: "AKIA123456789",
            secret_access_key: "secret_key",
            region: "us-west-2"
          }
        )
        post :add_cloud_remote, params: valid_params
      end

      it 'redirects with success notice' do
        post :add_cloud_remote, params: valid_params
        expect(response).to redirect_to(integrations_path)
        expect(flash[:notice]).to eq("☁️ Remote 'test_remote' connected!")
      end
    end

    context 'when service returns error' do
      before do
        allow(CloudStorage::ConfigureRemote).to receive(:new).and_return(
          double(call: { success: false, error: "Connection failed" })
        )
      end

      it 'redirects with error message' do
        post :add_cloud_remote, params: valid_params
        expect(response).to redirect_to(integrations_path)
        expect(flash[:alert]).to eq("Connection failed")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        post :add_cloud_remote, params: valid_params
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE #remove_cloud_remote' do
    let(:remote_name) { "test_remote" }

    before do
      allow(CloudStorage::ConfigureRemote).to receive(:delete_remote).and_return(true)
    end

    context 'when removal is successful' do
      it 'calls delete_remote service' do
        expect(CloudStorage::ConfigureRemote).to receive(:delete_remote).with(remote_name)
        delete :remove_cloud_remote, params: { remote_name: remote_name }
      end

      it 'redirects with success notice' do
        delete :remove_cloud_remote, params: { remote_name: remote_name }
        expect(response).to redirect_to(integrations_path)
        expect(flash[:notice]).to eq("Remote 'test_remote' removed")
      end
    end

    context 'when removal fails' do
      before do
        allow(CloudStorage::ConfigureRemote).to receive(:delete_remote).and_return(false)
      end

      it 'redirects with error message' do
        delete :remove_cloud_remote, params: { remote_name: remote_name }
        expect(response).to redirect_to(integrations_path)
        expect(flash[:alert]).to eq("Failed to remove remote")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        delete :remove_cloud_remote, params: { remote_name: remote_name }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET #test_cloud_remote' do
    let(:remote_name) { "test_remote" }

    context 'when remote info is available' do
      let(:remote_info) { { "type" => "s3", "region" => "us-west-2" } }

      before do
        allow(CloudStorage::ConfigureRemote).to receive(:remote_info).and_return(remote_info)
      end

      it 'returns success response with info' do
        get :test_cloud_remote, params: { remote_name: remote_name }
        expect(response).to be_successful
        json = JSON.parse(response.body)
        expect(json['status']).to eq('connected')
        expect(json['info']).to eq(remote_info)
      end
    end

    context 'when remote info is not available' do
      before do
        allow(CloudStorage::ConfigureRemote).to receive(:remote_info).and_return(nil)
      end

      it 'returns error response' do
        get :test_cloud_remote, params: { remote_name: remote_name }
        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['status']).to eq('error')
        expect(json['message']).to eq("Could not connect to test_remote")
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to sign in' do
        get :test_cloud_remote, params: { remote_name: remote_name }
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
