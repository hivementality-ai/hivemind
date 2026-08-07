# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Desktop pairing", type: :request do
  let(:user) { create(:user, :owner) }
  let(:code_verifier) { "a-very-secret-code-verifier" }
  let(:code_challenge) { Digest::SHA256.hexdigest(code_verifier) }
  let(:valid_params) do
    { device_name: "Desktop: MacBook", code_challenge: code_challenge, state: "abc123", port: "51234" }
  end

  describe "GET /desktop_pairing/authorize" do
    it "requires login" do
      get new_desktop_pairing_path, params: valid_params
      expect(response).to redirect_to(new_user_session_path)
    end

    it "renders the approval page for a logged-in user" do
      sign_in user
      get new_desktop_pairing_path, params: valid_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Desktop: MacBook")
    end

    it "opts both forms out of Turbo so the loopback redirect is a top-level navigation" do
      sign_in user
      get new_desktop_pairing_path, params: valid_params

      # Without data-turbo=false, Turbo follows the 302 to http://127.0.0.1
      # with fetch, which the browser blocks cross-origin — the exchange code
      # never reaches the desktop app.
      expect(response.body.scan(/data-turbo="false"/).size).to eq(2)
    end

    it "rejects requests missing required params" do
      sign_in user
      get new_desktop_pairing_path, params: valid_params.except(:code_challenge)

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST /desktop_pairing/authorize (approve)" do
    it "requires login" do
      post desktop_pairing_path, params: valid_params
      expect(response).to redirect_to(new_user_session_path)
    end

    it "mints a one-time code and redirects only to the 127.0.0.1 loopback" do
      sign_in user

      expect {
        post desktop_pairing_path, params: valid_params
      }.to change(DesktopPairingCode, :count).by(1)

      pairing_code = DesktopPairingCode.last
      expect(pairing_code.user).to eq(user)
      expect(pairing_code.device_name).to eq("Desktop: MacBook")
      expect(pairing_code.code_challenge).to eq(code_challenge)

      expect(response).to redirect_to(
        "http://127.0.0.1:51234/callback?code=#{pairing_code.code}&state=abc123"
      )
    end

    it "never includes a raw ApiToken in the redirect" do
      sign_in user
      post desktop_pairing_path, params: valid_params

      expect(response.headers["Location"]).not_to include("hv_")
    end

    it "rejects a non-numeric port instead of redirecting off-loopback" do
      sign_in user
      post desktop_pairing_path, params: valid_params.merge(port: "51234evil.com")

      expect(response).to have_http_status(:bad_request)
      expect(DesktopPairingCode.count).to eq(0)
    end

    it "rejects an out-of-range port" do
      sign_in user
      post desktop_pairing_path, params: valid_params.merge(port: "70000")

      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a missing state or code_challenge" do
      sign_in user
      post desktop_pairing_path, params: valid_params.except(:state)

      expect(response).to have_http_status(:bad_request)
      expect(DesktopPairingCode.count).to eq(0)
    end
  end

  describe "POST /desktop_pairing/deny" do
    it "redirects to the loopback with an error and mints no code" do
      sign_in user

      expect {
        post deny_desktop_pairing_path, params: { state: "abc123", port: "51234" }
      }.not_to change(DesktopPairingCode, :count)

      expect(response).to redirect_to("http://127.0.0.1:51234/callback?error=access_denied&state=abc123")
    end
  end

  describe "POST /desktop_pairing/exchange" do
    let!(:pairing_code) { create(:desktop_pairing_code, user: user, code_challenge: code_challenge) }

    it "works without any authentication" do
      post exchange_desktop_pairing_path, params: { code: pairing_code.code, code_verifier: code_verifier }
      expect(response).to have_http_status(:ok)
    end

    it "returns a raw ApiToken for the approving user with the device name" do
      expect {
        post exchange_desktop_pairing_path, params: { code: pairing_code.code, code_verifier: code_verifier }
      }.to change(ApiToken, :count).by(1)

      token = ApiToken.last
      expect(token.user).to eq(user)
      expect(token.name).to eq(pairing_code.device_name)

      json = JSON.parse(response.body)
      expect(json["token"]).to start_with("hv_")
      expect(ApiToken.authenticate(json["token"])).to eq(token)
    end

    it "rejects the wrong code_verifier" do
      post exchange_desktop_pairing_path, params: { code: pairing_code.code, code_verifier: "wrong-verifier" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ApiToken.count).to eq(0)
    end

    it "rejects an expired code" do
      expired = create(:desktop_pairing_code, :expired, user: user, code_challenge: code_challenge)

      post exchange_desktop_pairing_path, params: { code: expired.code, code_verifier: code_verifier }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects an unknown code" do
      post exchange_desktop_pairing_path, params: { code: "not-a-real-code", code_verifier: code_verifier }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "is single-use: a second exchange with the same code fails" do
      post exchange_desktop_pairing_path, params: { code: pairing_code.code, code_verifier: code_verifier }
      expect(response).to have_http_status(:ok)

      expect {
        post exchange_desktop_pairing_path, params: { code: pairing_code.code, code_verifier: code_verifier }
      }.not_to change(ApiToken, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
