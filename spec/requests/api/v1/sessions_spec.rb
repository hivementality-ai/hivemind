# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Sessions", type: :request do
  let(:user) { create(:user, :owner) }
  let(:api_token) { create(:api_token, user: user) }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.raw_token}" } }
  let(:agent) { create(:agent) }

  describe "POST /api/v1/sessions" do
    it "requires authentication" do
      post "/api/v1/sessions", params: { agent_id: agent.id }
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates a session for an agent found by id" do
      expect {
        post "/api/v1/sessions", params: { agent_id: agent.id }, headers: auth_headers
      }.to change(Session, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["session_key"]).to be_present
      expect(json["status"]).to eq("active")
    end

    it "creates a session for an agent found by slug" do
      post "/api/v1/sessions", params: { agent_id: agent.slug }, headers: auth_headers

      expect(response).to have_http_status(:created)
      expect(Session.last.agent).to eq(agent)
    end

    it "sets session attributes exactly like the web create flow" do
      post "/api/v1/sessions", params: { agent_id: agent.slug }, headers: auth_headers

      new_session = Session.last
      expect(new_session.session_key).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      expect(new_session.status).to eq("active")
      expect(new_session.transcript).to eq([])
      expect(new_session.metadata["started_by"]).to eq(user.id)
    end

    it "fires the session_created hook" do
      expect(Plugins::Hooks).to receive(:trigger).with("session_created", session: instance_of(Session))

      post "/api/v1/sessions", params: { agent_id: agent.slug }, headers: auth_headers
    end

    it "returns 404 for an unknown agent" do
      post "/api/v1/sessions", params: { agent_id: "does-not-exist" }, headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/sessions/:id" do
    let(:session_record) do
      create(:session, agent: agent, transcript: [
        { "role" => "user", "content" => "Hello", "timestamp" => 1.hour.ago.iso8601 },
        { "role" => "assistant", "content" => "Hi there!", "timestamp" => 1.hour.ago.iso8601 }
      ])
    end

    it "requires authentication" do
      get "/api/v1/sessions/#{session_record.session_key}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns the full transcript and processing flag" do
      get "/api/v1/sessions/#{session_record.session_key}", headers: auth_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["transcript"]).to eq(session_record.transcript)
      expect(json["transcript"].size).to eq(2)
      expect(json).to have_key("processing")
      expect(json["processing"]).to eq(false)
    end

    it "reports processing true while the session is mid-stream" do
      Redis.current.setex("session_processing:#{session_record.id}", 60, "1")

      get "/api/v1/sessions/#{session_record.session_key}", headers: auth_headers

      expect(JSON.parse(response.body)["processing"]).to eq(true)
    ensure
      Redis.current.del("session_processing:#{session_record.id}")
    end
  end

  describe "POST /api/v1/sessions/:id/messages" do
    let(:session_record) { create(:session, agent: agent) }

    before do
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "requires authentication" do
      post "/api/v1/sessions/#{session_record.session_key}/messages", params: { message: "hi" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "enqueues ChatStreamJob and broadcasts user_message" do
      expect {
        post "/api/v1/sessions/#{session_record.session_key}/messages",
             params: { message: "Hello assistant!" }, headers: auth_headers
      }.to have_enqueued_job(ChatStreamJob).with(session_record.id, "Hello assistant!", [])

      expect(response).to have_http_status(:accepted)
      expect(ActionCable.server).to have_received(:broadcast).with(
        "session_#{session_record.id}",
        hash_including(type: "user_message", content: "Hello assistant!")
      )
    end

    it "returns 422 for a blank message with no attachments" do
      post "/api/v1/sessions/#{session_record.session_key}/messages",
           params: { message: "" }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates chat attachments for uploaded images" do
      file = fixture_file_upload(Rails.root.join("spec/fixtures/files/test_image.png"), "image/png")

      expect {
        post "/api/v1/sessions/#{session_record.session_key}/messages",
             params: { message: "check this out", images: [ file ] }, headers: auth_headers
      }.to change { session_record.chat_attachments.count }.by(1)

      expect(response).to have_http_status(:accepted)
    end

    context "when there is a pending ask_user question" do
      before do
        allow(Sessions::ResolvePendingQuestion).to receive(:call).and_return(ServiceResponse.success)
      end

      it "routes the reply through ResolvePendingQuestion instead of enqueuing a new job" do
        expect(ChatStreamJob).not_to receive(:perform_later)

        post "/api/v1/sessions/#{session_record.session_key}/messages",
             params: { message: "42" }, headers: auth_headers

        expect(Sessions::ResolvePendingQuestion).to have_received(:call).with(session: session_record, user_message: "42")
        expect(response).to have_http_status(:accepted)
      end
    end
  end

  describe "POST /api/v1/sessions/:id/interrupt" do
    let(:session_record) { create(:session, agent: agent) }

    before do
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "requires authentication" do
      post "/api/v1/sessions/#{session_record.session_key}/interrupt", params: { type: "cancel" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "sends a cancel signal" do
      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "cancel" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["type"]).to eq("cancel")
      expect(SessionSignal.peek(session_record.id)).to include(type: "cancel")
    end

    it "sends a redirect signal with a message" do
      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "redirect", message: "look at the other file instead" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(SessionSignal.peek(session_record.id)).to include(type: "redirect", message: "look at the other file instead")
    end

    it "sends an inject signal with a message" do
      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "inject", message: "also check the tests" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(SessionSignal.peek(session_record.id)).to include(type: "inject")
    end

    it "rejects an invalid signal type" do
      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "bogus" }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "requires a message for redirect" do
      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "redirect", message: "" }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "broadcasts interrupt_sent" do
      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "cancel" }, headers: auth_headers

      expect(ActionCable.server).to have_received(:broadcast).with(
        "session_#{session_record.id}",
        { type: "interrupt_sent", signal_type: "cancel", message: nil }
      )
    end

    it "propagates the signal to running sub-agent child sessions" do
      child_session = create(:session, agent: agent)
      create(:sub_agent_task, :running, parent_session: session_record, child_session: child_session)

      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "cancel" }, headers: auth_headers

      expect(SessionSignal.peek(child_session.id)).to include(type: "cancel")
    end

    it "does not propagate to non-running sub-agent child sessions" do
      child_session = create(:session, agent: agent)
      create(:sub_agent_task, :completed, parent_session: session_record, child_session: child_session)

      post "/api/v1/sessions/#{session_record.session_key}/interrupt",
           params: { type: "cancel" }, headers: auth_headers

      expect(SessionSignal.peek(child_session.id)).to be_nil
    end
  end

  describe "PATCH /api/v1/sessions/:id" do
    let(:session_record) { create(:session, agent: agent, title: nil) }

    before do
      allow(ActionCable.server).to receive(:broadcast)
    end

    it "requires authentication" do
      patch "/api/v1/sessions/#{session_record.session_key}", params: { title: "New Title" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "renames the session and broadcasts title_update" do
      patch "/api/v1/sessions/#{session_record.session_key}", params: { title: "New Title" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(session_record.reload.title).to eq("New Title")
      expect(ActionCable.server).to have_received(:broadcast).with(
        "session_#{session_record.id}",
        { type: "title_update", title: "New Title" }
      )
    end

    it "rejects a blank title" do
      patch "/api/v1/sessions/#{session_record.session_key}", params: { title: "  " }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a title over 100 characters" do
      patch "/api/v1/sessions/#{session_record.session_key}", params: { title: "A" * 101 }, headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
