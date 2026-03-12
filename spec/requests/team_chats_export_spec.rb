# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Team Chat Export", type: :request do
  let(:user) { create(:user, :owner) }
  let(:team) { create(:team) }
  let(:chat_session) { create(:team_chat_session, team: team, user: user) }

  before { sign_in user }

  describe "GET /team_chats/:id/export" do
    it "returns a JSON file download" do
      get export_team_chat_path(chat_session)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("team_chat_#{chat_session.id}_export")
    end

    it "contains valid export JSON" do
      get export_team_chat_path(chat_session)
      export = JSON.parse(response.body)
      expect(export["version"]).to eq("1.0")
      expect(export["team_chat"]["id"]).to eq(chat_session.id)
      expect(export["team"]["name"]).to eq(team.name)
      expect(export["timeline"]).to be_an(Array)
    end
  end

  describe "GET /team_chats/:id/export (unauthenticated)" do
    before { sign_out user }

    it "redirects to login" do
      get export_team_chat_path(chat_session)
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
