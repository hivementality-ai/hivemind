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

    it "flags quotes that were not found in their sources" do
      checks = { "results" => [ { "passage" => "a made up line of eight or more words", "source_url" => "u", "status" => "unverified" } ],
                 "summary" => { "total" => 3, "verified" => 2, "other_source" => 0, "unverified" => 1 } }
      rs = create(:research_session, :completed, agent: agent, session: session_record, quote_checks: checks)
      get research_session_path(rs)
      expect(response.body).to include("1 of 3 quotes could not be found in their sources")
      expect(response.body).to include("a made up line of eight or more words")
      expect(response.body).to include("(not found in source)")
    end

    it "flags quotes found in a different source than cited, naming the host" do
      checks = { "results" => [ { "passage" => "a misattributed line of eight or more words", "source_url" => "https://other.example.org/p", "status" => "other_source" },
                                { "passage" => "a made up line of eight or more words", "source_url" => "u", "status" => "unverified" } ],
                 "summary" => { "total" => 9, "verified" => 7, "other_source" => 1, "unverified" => 1 } }
      rs = create(:research_session, :completed, agent: agent, session: session_record, quote_checks: checks)
      get research_session_path(rs)
      expect(response.body).to include("1 of 9 quotes could not be found, 1 was in a different source than cited")
      expect(response.body).to include("(found in a different source: other.example.org)")
    end

    it "shows no quote warning when every quote was verified" do
      rs = create(:research_session, :completed, agent: agent, session: session_record)
      get research_session_path(rs)
      expect(response.body).not_to include("could not be found in their sources")
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
