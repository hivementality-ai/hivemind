# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api tokens", type: :request do
  describe "as an owner" do
    let(:user) { create(:user, :owner) }
    before { sign_in user }

    it "lists tokens without exposing any plaintext" do
      token = create(:api_token, user: user, name: "CI deploy")
      get api_tokens_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CI deploy")
      expect(response.body).not_to include(token.token_digest)
    end

    it "creates a token and shows plaintext exactly once in flash" do
      post api_tokens_path, params: { api_token: { name: "My Token" } }

      expect(response).to redirect_to(api_tokens_path)
      follow_redirect!

      token = ApiToken.last
      expect(token.name).to eq("My Token")
      expect(token.user).to eq(user)
      expect(response.body).to include("hv_")
    end

    it "re-renders index with error on missing name" do
      post api_tokens_path, params: { api_token: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "revokes a token so it can no longer authenticate" do
      token = create(:api_token, user: user, name: "Disposable")
      raw = "hv_#{SecureRandom.urlsafe_base64(32)}"
      token.update!(token_digest: Digest::SHA256.hexdigest(raw))

      delete api_token_path(token)
      expect(response).to redirect_to(api_tokens_path)

      token.reload
      expect(token.revoked?).to be true
      expect(ApiToken.authenticate(raw)).to be_nil
    end
  end

  describe "as a viewer" do
    before { sign_in create(:user, :viewer) }

    it "is denied access to index" do
      get api_tokens_path
      expect(response).to redirect_to(root_path)
    end

    it "is denied access to create" do
      post api_tokens_path, params: { api_token: { name: "Sneaky" } }
      expect(response).to redirect_to(root_path)
    end
  end
end
