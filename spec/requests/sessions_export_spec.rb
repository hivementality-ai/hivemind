# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session Export", type: :request do
  let(:user) { create(:user, :owner) }
  let(:agent) { create(:agent) }
  let(:session) { create(:session, :with_transcript, agent: agent) }

  before { sign_in user }

  describe "GET /sessions/:id/export" do
    it "returns a JSON file download" do
      get export_session_path(session)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("session_#{session.id}_export")
    end

    it "contains valid export JSON" do
      get export_session_path(session)
      export = JSON.parse(response.body)
      expect(export["version"]).to eq("1.0")
      expect(export["session"]["id"]).to eq(session.id)
      expect(export["agent"]["name"]).to eq(agent.name)
      expect(export["timeline"]).to be_an(Array)
    end
  end

  describe "GET /sessions/:id/export (unauthenticated)" do
    before { sign_out user }

    it "redirects to login" do
      get export_session_path(session)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
