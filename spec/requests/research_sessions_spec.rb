# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ResearchSessions", type: :request do
  let(:user) { create(:user) }
  let(:agent) { create(:agent) }
  let(:session_record) { create(:session, agent: agent) }

  before { sign_in user }

  describe "GET /research" do
    it "lists research sessions" do
      create(:research_session, :completed, agent: agent, session: session_record)
      create(:research_session, :running,   agent: agent, session: session_record)

      get research_sessions_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Research Sessions")
      expect(response.body).to include("completed")
      expect(response.body).to include("running")
    end

    it "redirects unauthenticated users" do
      sign_out user
      get research_sessions_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe "GET /research/:id" do
    it "shows a completed session with its report" do
      rs = create(:research_session, :completed, agent: agent, session: session_record)
      get research_session_path(rs)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(rs.query)
      # report is embedded as HTML data attribute for client-side markdown rendering
      expect(response.body).to include(ERB::Util.html_escape(rs.report))
    end

    it "shows a running session with phase info" do
      rs = create(:research_session, :running, agent: agent, session: session_record)
      get research_session_path(rs)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("running")
    end

    it "shows a failed session with error message" do
      rs = create(:research_session, :failed, agent: agent, session: session_record)
      get research_session_path(rs)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("failed")
      expect(response.body).to include(rs.error_message)
    end

    it "returns 404 for missing id" do
      get research_session_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
