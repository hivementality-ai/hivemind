# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clawhub::Client do
  describe ".search" do
    it "returns normalized results" do
      stub_request(:get, "https://clawhub.ai/api/v1/search")
        .with(query: { q: "git", limit: "24" })
        .to_return(status: 200, body: {
          results: [
            {
              slug: "git", displayName: "Git", summary: "Git things",
              ownerHandle: "ivan", downloads: 17_138
            }
          ]
        }.to_json)

      result = described_class.search("git")

      expect(result).to be_success
      expect(result.data).to eq([
        { slug: "git", name: "Git", description: "Git things",
          author: "ivan", downloads: 17_138, version: nil }
      ])
    end

    it "fails gracefully when the registry is unreachable" do
      stub_request(:get, %r{clawhub\.ai/api/v1/search}).to_timeout

      result = described_class.search("git")

      expect(result).to be_failure
      expect(result.error).to include("Couldn't reach ClawHub")
    end

    it "fails gracefully on non-200 responses" do
      stub_request(:get, %r{clawhub\.ai/api/v1/search}).to_return(status: 500)

      expect(described_class.search("git")).to be_failure
    end
  end

  describe ".popular" do
    it "normalizes catalog items (stats.downloads, latestVersion.version)" do
      stub_request(:get, "https://clawhub.ai/api/v1/skills")
        .with(query: { sort: "downloads", limit: "24" })
        .to_return(status: 200, body: {
          items: [
            {
              slug: "self-improving-agent", displayName: "self improving agent",
              summary: "Learns", stats: { downloads: 471_469 },
              latestVersion: { version: "4.0.1" }
            }
          ]
        }.to_json)

      result = described_class.popular

      expect(result).to be_success
      expect(result.data.first).to include(
        slug: "self-improving-agent", downloads: 471_469, version: "4.0.1", author: nil
      )
    end
  end

  describe ".fetch_skill_md" do
    it "returns raw SKILL.md content" do
      stub_request(:get, "https://clawhub.ai/api/v1/skills/git/file")
        .with(query: { path: "SKILL.md" })
        .to_return(status: 200, body: "---\nname: Git\n---\n\nBody")

      result = described_class.fetch_skill_md("git")

      expect(result).to be_success
      expect(result.data).to start_with("---\nname: Git")
    end

    it "fails gracefully on 404" do
      stub_request(:get, %r{clawhub\.ai/api/v1/skills/nope/file}).to_return(status: 404)

      expect(described_class.fetch_skill_md("nope")).to be_failure
    end
  end
end
