# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubReleaseChecker do
  describe ".newer?" do
    it "detects newer CalVer versions" do
      expect(described_class.send(:newer?, "2026.02.2", "2026.02.1")).to be true
      expect(described_class.send(:newer?, "2026.03.1", "2026.02.5")).to be true
      expect(described_class.send(:newer?, "2027.01.1", "2026.12.9")).to be true
    end

    it "returns false for same or older versions" do
      expect(described_class.send(:newer?, "2026.02.1", "2026.02.1")).to be false
      expect(described_class.send(:newer?, "2026.02.1", "2026.02.2")).to be false
      expect(described_class.send(:newer?, "2026.01.1", "2026.02.1")).to be false
    end

    it "handles blank values" do
      expect(described_class.send(:newer?, nil, "2026.02.1")).to be false
      expect(described_class.send(:newer?, "2026.02.1", nil)).to be false
    end
  end

  describe ".breaking_changes?" do
    it "detects breaking change markers" do
      expect(described_class.send(:breaking_changes?, "## ⚠️ BREAKING CHANGES")).to be true
      expect(described_class.send(:breaking_changes?, "This has breaking change notes")).to be true
      expect(described_class.send(:breaking_changes?, "BREAKING: schema changed")).to be true
    end

    it "returns false for normal release notes" do
      expect(described_class.send(:breaking_changes?, "Bug fixes and improvements")).to be false
      expect(described_class.send(:breaking_changes?, nil)).to be false
    end
  end

  describe ".update_info" do
    before do
      stub_const("Hivemind::VERSION", "2026.02.1")
      Rails.cache.clear
    end

    it "returns update info when newer version available" do
      allow(described_class).to receive(:fetch_latest_release).and_return({
        version: "2026.02.2",
        html_url: "https://github.com/hivementality-ai/hivemind/releases/tag/v2026.02.2",
        published_at: "2026-02-18T00:00:00Z",
        breaking_changes: false,
        body: "Bug fixes"
      })

      info = described_class.update_info
      expect(info[:current]).to eq("2026.02.1")
      expect(info[:latest]).to eq("2026.02.2")
      expect(info[:update_available]).to be true
    end

    it "returns no update when on latest" do
      allow(described_class).to receive(:fetch_latest_release).and_return({
        version: "2026.02.1",
        html_url: "https://github.com/hivementality-ai/hivemind/releases/tag/v2026.02.1",
        published_at: "2026-02-17T00:00:00Z",
        breaking_changes: false,
        body: "Initial release"
      })

      info = described_class.update_info
      expect(info[:update_available]).to be false
    end
  end
end
