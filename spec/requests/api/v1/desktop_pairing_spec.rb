# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::DesktopPairing", type: :request do
  describe "DELETE /api/v1/desktop_pairing/token" do
    let(:user) { create(:user, :owner) }

    it "requires a valid bearer ApiToken" do
      delete "/api/v1/desktop_pairing/token"
      expect(response).to have_http_status(:unauthorized)
    end

    it "revokes the token that authenticated the request, without a Devise session" do
      token = user.api_tokens.create!(name: "Desktop: MacBook")
      raw_token = token.raw_token

      delete "/api/v1/desktop_pairing/token", headers: { "Authorization" => "Bearer #{raw_token}" }

      expect(response).to have_http_status(:no_content)
      expect(ApiToken.authenticate(raw_token)).to be_nil
      expect(token.reload.revoked?).to be true
    end

    it "does not revoke other tokens belonging to the same user" do
      token = user.api_tokens.create!(name: "Desktop: MacBook")
      other_token = user.api_tokens.create!(name: "CI deploy")

      delete "/api/v1/desktop_pairing/token", headers: { "Authorization" => "Bearer #{token.raw_token}" }

      expect(other_token.reload.revoked?).to be false
    end

    it "rejects an already-revoked token" do
      token = user.api_tokens.create!(name: "Desktop: MacBook")
      raw_token = token.raw_token
      token.revoke!

      delete "/api/v1/desktop_pairing/token", headers: { "Authorization" => "Bearer #{raw_token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
