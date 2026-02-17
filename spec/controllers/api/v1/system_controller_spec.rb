# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SystemController, type: :controller do
  describe "GET #version" do
    context "with update check enabled" do
      before do
        allow(ENV).to receive(:fetch).with("UPDATE_CHECK_ENABLED", "true").and_return("true")
      end

      it "returns current version" do
        allow(GithubReleaseChecker).to receive(:update_info).and_return({
          current: "2026.02.1",
          latest: "2026.02.2",
          update_available: true,
          breaking_changes: false,
          changelog_url: "https://github.com/hivementality-ai/hivemind/releases/tag/v2026.02.2",
          published_at: "2026-02-17T00:00:00Z",
          last_checked: "2026-02-17T15:00:00Z"
        })

        get :version
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["current"]).to eq("2026.02.1")
        expect(json["latest"]).to eq("2026.02.2")
        expect(json["update_available"]).to be true
      end

      it "handles GitHub API failure gracefully" do
        allow(GithubReleaseChecker).to receive(:update_info).and_return(nil)

        get :version
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["current"]).to be_present
        expect(json["error"]).to eq("Unable to check for updates")
      end
    end

    context "with update check disabled" do
      before do
        allow(ENV).to receive(:fetch).with("UPDATE_CHECK_ENABLED", "true").and_return("false")
      end

      it "returns version without checking GitHub" do
        expect(GithubReleaseChecker).not_to receive(:update_info)

        get :version
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["current"]).to be_present
        expect(json["update_check_enabled"]).to be false
      end
    end
  end
end
