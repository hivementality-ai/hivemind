# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::HashtagActions", type: :request do
  describe "GET /api/v1/hashtag_actions" do
    it "returns list of hashtag actions with descriptions" do
      get "/api/v1/hashtag_actions"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json).to be_an(Array)
      expect(json.size).to eq(18)

      # Check structure
      action = json.first
      expect(action).to have_key("name")
      expect(action).to have_key("description")

      # Check specific actions exist
      action_names = json.map { |a| a["name"] }
      expect(action_names).to include("remember", "forget", "search", "todo", "schedule",
                                      "summarize", "status", "reset", "help", "mood",
                                      "voice", "image", "handoff", "delegate", "private",
                                      "approve", "deny")
    end

    it "includes correct descriptions" do
      get "/api/v1/hashtag_actions"

      json = JSON.parse(response.body)
      remember_action = json.find { |a| a["name"] == "remember" }

      expect(remember_action["description"]).to eq("Save something to memory")
    end
  end
end
