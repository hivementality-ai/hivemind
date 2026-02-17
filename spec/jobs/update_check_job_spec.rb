# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateCheckJob, type: :job do
  before { Rails.cache.clear }

  describe "#perform" do
    context "when update is available" do
      before do
        stub_const("Hivemind::VERSION", "2026.02.1")
        allow(GithubReleaseChecker).to receive(:latest_release).and_return({
          version: "2026.02.2",
          html_url: "https://github.com/hivementality-ai/hivemind/releases/tag/v2026.02.2",
          published_at: "2026-02-18T00:00:00Z",
          breaking_changes: false,
          body: "Bug fixes"
        })
        allow(GithubReleaseChecker).to receive(:newer?).and_return(true)
      end

      it "caches update info" do
        described_class.new.perform

        cached = Rails.cache.read("hivemind:update_available")
        expect(cached).to be_present
        expect(cached[:version]).to eq("2026.02.2")
        expect(cached[:current]).to eq("2026.02.1")
        expect(cached[:breaking]).to be false
      end
    end

    context "when already on latest" do
      before do
        stub_const("Hivemind::VERSION", "2026.02.2")
        allow(GithubReleaseChecker).to receive(:latest_release).and_return({
          version: "2026.02.2",
          html_url: "https://github.com/hivementality-ai/hivemind/releases/tag/v2026.02.2",
          published_at: "2026-02-18T00:00:00Z",
          breaking_changes: false,
          body: "Bug fixes"
        })
        allow(GithubReleaseChecker).to receive(:newer?).and_return(false)
      end

      it "clears cached update info" do
        Rails.cache.write("hivemind:update_available", { version: "old" })

        described_class.new.perform

        expect(Rails.cache.read("hivemind:update_available")).to be_nil
      end
    end

    context "when version is dev" do
      before { stub_const("Hivemind::VERSION", "dev") }

      it "skips check" do
        expect(GithubReleaseChecker).not_to receive(:latest_release)
        described_class.new.perform
      end
    end

    context "when update check is disabled" do
      before do
        allow(ENV).to receive(:fetch).with("UPDATE_CHECK_ENABLED", "true").and_return("false")
      end

      it "skips check" do
        expect(GithubReleaseChecker).not_to receive(:latest_release)
        described_class.new.perform
      end
    end

    context "when GitHub API fails" do
      before do
        stub_const("Hivemind::VERSION", "2026.02.1")
        allow(GithubReleaseChecker).to receive(:latest_release).and_raise(StandardError, "network error")
      end

      it "handles error gracefully" do
        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end
end
