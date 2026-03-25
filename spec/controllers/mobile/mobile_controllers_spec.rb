# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mobile::HomeController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns recent sessions" do
      agent = create(:agent)
      session = create(:session, agent: agent, status: :active, last_activity_at: Time.current)

      get :index
      expect(assigns(:recent_sessions)).to include(session)
    end

    it "assigns enabled agents" do
      agent = create(:agent, enabled: true)
      create(:agent, enabled: false)

      get :index
      expect(assigns(:agents)).to include(agent)
      expect(assigns(:agents).size).to eq(1)
    end

    it "uses mobile layout" do
      get :index
      expect(response).to render_template(layout: "mobile")
    end
  end
end

RSpec.describe Mobile::SessionsController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns sessions ordered by activity" do
      old_session = create(:session, agent: agent, status: :active, last_activity_at: 2.hours.ago)
      new_session = create(:session, agent: agent, status: :active, last_activity_at: 1.minute.ago)

      get :index
      sessions = assigns(:sessions)
      expect(sessions.first).to eq(new_session)
      expect(sessions.last).to eq(old_session)
    end
  end

  describe "GET #show" do
    let(:session_record) { create(:session, agent: agent, status: :active) }

    it "returns a successful response" do
      get :show, params: { id: session_record.id }
      expect(response).to be_successful
    end

    it "assigns session and agent" do
      get :show, params: { id: session_record.id }
      expect(assigns(:session)).to eq(session_record)
      expect(assigns(:agent)).to eq(agent)
    end
  end

  describe "POST #message" do
    let(:session_record) { create(:session, agent: agent, status: :active) }

    before do
      allow(Sessions::ResolvePendingQuestion).to receive(:call).and_return(
        ServiceResponse.failure(error: "no pending")
      )
      allow(ChatStreamJob).to receive(:perform_later)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "enqueues a ChatStreamJob" do
      post :message, params: { id: session_record.id, message: "Hello" }
      expect(response).to have_http_status(:ok)
      expect(ChatStreamJob).to have_received(:perform_later).with(session_record.id, "Hello", [])
    end

    it "rejects blank messages with no attachments" do
      post :message, params: { id: session_record.id, message: "" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "broadcasts user message for instant feedback" do
      post :message, params: { id: session_record.id, message: "Test" }
      expect(ActionCable.server).to have_received(:broadcast).with(
        "session_#{session_record.id}",
        hash_including(type: "user_message", content: "Test")
      )
    end
  end

  describe "POST #interrupt" do
    let(:session_record) { create(:session, agent: agent, status: :active) }

    before do
      allow(SessionSignal).to receive(:set)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "sends a cancel signal" do
      post :interrupt, params: { id: session_record.id, type: "cancel" }
      expect(response).to have_http_status(:ok)
      expect(SessionSignal).to have_received(:set).with(session_record.id, type: "cancel", message: nil)
    end

    it "rejects invalid signal types" do
      post :interrupt, params: { id: session_record.id, type: "invalid" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires message for redirect signal" do
      post :interrupt, params: { id: session_record.id, type: "redirect", message: "" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

RSpec.describe Mobile::AgentsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns enabled agents" do
      enabled = create(:agent, enabled: true)
      create(:agent, enabled: false)

      get :index
      expect(assigns(:agents)).to eq([ enabled ])
    end
  end

  describe "GET #show" do
    it "returns a successful response for valid slug" do
      agent = create(:agent, name: "TestAgent")
      get :show, params: { slug: agent.slug }
      expect(response).to be_successful
    end

    it "redirects with alert for invalid slug" do
      get :show, params: { slug: "nonexistent-agent" }
      expect(response).to redirect_to(mobile_agents_path)
      expect(flash[:alert]).to eq("Agent not found")
    end
  end
end

RSpec.describe Mobile::TeamChatsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end
  end

  describe "GET #show" do
    let(:team) { create(:team) }
    let(:agent) { create(:agent, team: team) }
    let(:chat_session) { create(:team_chat_session, team: team, user: user) }

    it "returns a successful response" do
      get :show, params: { id: chat_session.id }
      expect(response).to be_successful
    end
  end
end

RSpec.describe Mobile::ActivityController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "includes recent session messages in the feed" do
      agent = create(:agent)
      create(:session, agent: agent, status: :active,
        last_activity_at: 1.hour.ago,
        transcript: [ { "role" => "assistant", "content" => "Hello from agent" } ])

      get :index
      events = assigns(:events)
      expect(events.any? { |e| e[:type] == "message" }).to be true
    end

    it "handles empty state gracefully" do
      get :index
      expect(assigns(:events)).to eq([])
    end
  end
end

RSpec.describe Mobile::SettingsController, type: :controller do
  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "assigns default notification preferences" do
      get :index
      prefs = assigns(:notification_preferences)
      expect(prefs["agent_responses"]).to be true
      expect(prefs["heartbeat_findings"]).to be false
    end

    it "merges user preferences over defaults" do
      user.update!(notification_preferences: { "agent_responses" => false })
      get :index
      prefs = assigns(:notification_preferences)
      expect(prefs["agent_responses"]).to be false
      expect(prefs["task_completions"]).to be true # default preserved
    end
  end

  describe "PATCH #update_preferences" do
    it "saves notification preferences" do
      patch :update_preferences, params: {
        preferences: { "agent_responses" => "1", "task_completions" => "0",
                        "budget_alerts" => "1", "heartbeat_findings" => "0" }
      }
      expect(response).to redirect_to(mobile_settings_path)

      user.reload
      expect(user.notification_preferences["agent_responses"]).to be true
      expect(user.notification_preferences["task_completions"]).to be false
    end

    it "rejects unknown preference keys" do
      patch :update_preferences, params: {
        preferences: { "agent_responses" => "1", "evil_key" => "1" }
      }
      user.reload
      expect(user.notification_preferences).not_to have_key("evil_key")
    end
  end

  describe "POST #push_subscription" do
    it "creates a push subscription" do
      post :push_subscription, params: {
        subscription: { endpoint: "https://push.example.com/123", p256dh: "abc123key", auth: "authkey" }
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(PushSubscription.count).to eq(1)
      sub = PushSubscription.first
      expect(sub.user).to eq(user)
      expect(sub.endpoint).to eq("https://push.example.com/123")
    end

    it "updates existing subscription for same endpoint" do
      PushSubscription.create!(user: user, endpoint: "https://push.example.com/123",
                               p256dh: "old", auth: "old")

      post :push_subscription, params: {
        subscription: { endpoint: "https://push.example.com/123", p256dh: "new_key", auth: "new_auth" }
      }, as: :json

      expect(PushSubscription.count).to eq(1)
      expect(PushSubscription.first.p256dh).to eq("new_key")
    end

    it "rejects missing parameters" do
      post :push_subscription, params: { subscription: { endpoint: "" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

RSpec.describe MobileDetector, type: :controller do
  # Test the mobile? helper via an anonymous controller
  controller(ApplicationController) do
    include MobileDetector

    def index
      render plain: mobile? ? "mobile" : "desktop"
    end
  end

  let(:user) { create(:user, :owner) }

  before do
    sign_in user
    Setting.set("setup_complete", "true")
    routes.draw { get "index" => "anonymous#index" }
  end

  it "detects mobile user agents" do
    request.headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)"
    get :index
    # Anonymous controller path has no mobile equivalent, so no redirect — but mobile? returns true
    expect(response.body).to eq("mobile")
  end

  it "does not detect desktop user agents as mobile" do
    request.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    get :index
    expect(response.body).to eq("desktop")
  end

  it "respects ?desktop=1 override" do
    request.headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)"
    get :index, params: { desktop: "1" }
    expect(response.body).to eq("desktop")
    expect(response.cookies["hivemind_view_pref"]).to eq("desktop")
  end

  it "respects ?mobile=1 override on desktop" do
    request.headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    get :index, params: { mobile: "1" }
    expect(response.body).to eq("mobile")
  end

  it "respects desktop cookie preference over user agent" do
    request.cookies["hivemind_view_pref"] = "desktop"
    request.headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)"
    get :index
    expect(response.body).to eq("desktop")
  end

  it "detects Android mobile user agents" do
    request.headers["User-Agent"] = "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
    get :index
    expect(response.body).to eq("mobile")
  end
end
