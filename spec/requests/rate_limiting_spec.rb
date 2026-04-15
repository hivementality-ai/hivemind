# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  describe "general IP throttle (300 req / 5 min)" do
    it "returns 429 after 300 requests" do
      300.times do
        get "/up"
        expect(response.status).to be < 500
      end

      get "/up"
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "login throttle (5 attempts / 20 sec)" do
    it "returns 429 after 5 login attempts from the same IP" do
      5.times do
        post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
      end

      post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "authenticated API throttle (60 req/min per token)" do
    it "returns 429 after 60 requests with the same Bearer token" do
      token = "test-api-token-abc123"

      60.times do
        get "/api/v1/agents", headers: { "Authorization" => "Bearer #{token}" }
      end

      get "/api/v1/agents", headers: { "Authorization" => "Bearer #{token}" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "chat message throttle (30 req/min per IP+session)" do
    let(:user) { create(:user, :owner) }
    let(:agent) { create(:agent) }
    let(:session) { create(:session, agent: agent) }
    let(:team) { create(:team) }
    let(:team_chat_session) { create(:team_chat_session, team: team, user: user) }

    before { sign_in user }

    it "returns 429 after 30 messages to the same session" do
      30.times do
        post "/sessions/#{session.id}/message", params: { message: "hello" }
      end

      post "/sessions/#{session.id}/message", params: { message: "hello" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "returns 429 after 30 messages to the same team chat" do
      30.times do
        post "/team_chats/#{team_chat_session.id}/message", params: { message: "hello" }
      end

      post "/team_chats/#{team_chat_session.id}/message", params: { message: "hello" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "webhook throttle (120 req/min per IP)" do
    it "returns 429 after 120 webhook requests" do
      120.times do
        post "/webhooks/slack"
      end

      post "/webhooks/slack"
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "429 response headers" do
    it "includes Retry-After and X-RateLimit-* headers" do
      5.times do
        post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
      end

      post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
      expect(response).to have_http_status(:too_many_requests)

      expect(response.headers["Retry-After"]).to be_present
      expect(response.headers["X-RateLimit-Limit"]).to be_present
      expect(response.headers["X-RateLimit-Remaining"]).to eq("0")
      expect(response.headers["X-RateLimit-Reset"]).to be_present
    end

    it "returns JSON error body" do
      5.times do
        post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
      end

      post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
      expect(response).to have_http_status(:too_many_requests)

      body = JSON.parse(response.body)
      expect(body["error"]).to match(/Rate limit exceeded/)
    end
  end


  describe "ClawHub install throttle (5 req/min per IP)" do
    let(:user) { create(:user, :owner) }

    before { sign_in user }

    it "returns 429 after 5 install requests from the same IP" do
      allow(ClawHub::SkillInstaller).to receive(:call).and_return(
        ServiceResponse.success(data: { skill: nil, scan_result: {}, status: "blocked" })
      )

      5.times do
        post "/clawhub/some-skill/install"
        expect(response.status).to be < 500
      end

      post "/clawhub/some-skill/install"
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "blocklisted IP" do
    it "returns 403 for a banned IP" do
      # Allow2Ban bans after 20 failed login attempts within 1 minute
      21.times do
        post "/users/sign_in", params: { user: { email: "test@example.com", password: "wrong" } }
      end

      # The IP should now be banned — next request gets 403
      get "/up"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
