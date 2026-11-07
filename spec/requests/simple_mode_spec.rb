# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Simple mode", type: :request do
  let(:owner) { create(:user, :owner) }

  before { sign_in owner }

  describe "sidebar" do
    it "shows the power-user entries when off" do
      get agents_path

      [ teams_path, team_chats_index_path, hooks_overview_path, budgets_path,
        api_tokens_path, webhook_endpoints_path ].each do |path|
        expect(response.body).to include(%(href="#{path}")), "missing nav link #{path}"
      end
    end

    it "hides them when on while the routes keep working" do
      SimpleMode.enabled = true
      get agents_path

      [ teams_path, team_chats_index_path, hooks_overview_path, budgets_path,
        api_tokens_path, webhook_endpoints_path ].each do |path|
        expect(response.body).not_to include(%(href="#{path}")), "nav link #{path} should be hidden"
      end
      expect(response.body).to include(%(href="#{providers_path}"))

      get api_tokens_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "integrations page" do
    it "hides the Jira and Trello sections when on" do
      SimpleMode.enabled = true
      get integrations_path

      expect(response.body).not_to include(update_jira_integrations_path)
      expect(response.body).not_to include(update_trello_integrations_path)
    end

    it "shows them when off" do
      get integrations_path

      expect(response.body).to include(update_trello_integrations_path).and include(update_jira_integrations_path)
    end
  end

  describe "channel platforms" do
    it "offers only iMessage, email and Slack when on" do
      SimpleMode.enabled = true
      get new_channel_path

      expect(response.body).to include(%(value="slack"), %(value="email"), %(value="imessage"))
      expect(response.body).not_to include(%(value="discord"))
    end
  end

  describe "PATCH /simple_mode" do
    it "turns it on and back off" do
      patch simple_mode_path, params: { enabled: "true" }
      expect(SimpleMode.enabled?).to be(true)

      patch simple_mode_path, params: { enabled: "false" }
      expect(SimpleMode.enabled?).to be(false)
    end

    it "is refused for a non-admin" do
      sign_out owner
      sign_in create(:user)

      patch simple_mode_path, params: { enabled: "true" }

      expect(SimpleMode.enabled?).to be(false)
    end
  end
end
