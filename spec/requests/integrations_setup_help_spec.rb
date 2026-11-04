# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integrations setup help", type: :request do
  before { sign_in create(:user) }

  describe "Google Workspace card" do
    it "walks through the consent screen and test user steps" do
      get integrations_path

      expect(response.body).to include("OAuth consent screen", "add yourself as a test user")
    end

    it "names the credentials button Save credentials" do
      get integrations_path

      expect(response.body).to include('value="Save credentials"')
      expect(response.body).not_to include("Save &amp; Connect")
    end

    it "warns when served from a plain http LAN address" do
      get integrations_path

      expect(response.body).to include("gws-redirect-warning")
    end

    it "does not warn on localhost" do
      host! "localhost"
      get integrations_path

      expect(response.body).not_to include("gws-redirect-warning")
    end

    it "does not warn over https" do
      https!
      get integrations_path

      expect(response.body).not_to include("gws-redirect-warning")
    end
  end

  describe "MCP servers card" do
    it "shows the count and links to the MCP servers screen" do
      create_list(:mcp_server, 2)

      get integrations_path

      expect(response.body).to include("2 MCP servers configured")
      expect(response.body).to include(%(href="#{mcp_servers_path}"))
    end
  end
end
