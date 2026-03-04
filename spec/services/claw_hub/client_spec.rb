# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClawHub::Client do
  subject(:client) { described_class.new }

  let(:base_url) { "https://clawhub.ai" }

  describe "#list_skills" do
    it "fetches trending skills" do
      stub_request(:get, "#{base_url}/api/v1/skills")
        .with(query: { limit: 20, sort: "trending" })
        .to_return(
          status: 200,
          body: { items: [{ slug: "test-skill", displayName: "Test Skill" }], nextCursor: "abc" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.list_skills
      expect(result["items"]).to be_an(Array)
      expect(result["items"].first["slug"]).to eq("test-skill")
      expect(result["nextCursor"]).to eq("abc")
    end

    it "passes cursor and sort params" do
      stub_request(:get, "#{base_url}/api/v1/skills")
        .with(query: { limit: 10, sort: "popular", cursor: "xyz" })
        .to_return(
          status: 200,
          body: { items: [], nextCursor: nil }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.list_skills(limit: 10, cursor: "xyz", sort: "popular")
      expect(result["items"]).to eq([])
    end

    it "raises ApiError on non-2xx" do
      stub_request(:get, "#{base_url}/api/v1/skills")
        .with(query: { limit: 20, sort: "trending" })
        .to_return(status: 500, body: "Internal Server Error")

      expect { client.list_skills }.to raise_error(ClawHub::ApiError, /500/)
    end
  end

  describe "#search_skills" do
    it "searches by query" do
      stub_request(:get, "#{base_url}/api/v1/search")
        .with(query: { q: "coding", limit: 20 })
        .to_return(
          status: 200,
          body: { results: [{ slug: "coding-helper", displayName: "Coding Helper", score: 0.95 }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.search_skills(query: "coding")
      expect(result["results"].first["slug"]).to eq("coding-helper")
    end
  end

  describe "#get_skill" do
    it "fetches skill detail by slug" do
      stub_request(:get, "#{base_url}/api/v1/skills/my-skill")
        .to_return(
          status: 200,
          body: {
            skill: { slug: "my-skill", displayName: "My Skill", stats: { downloads: 100 } },
            latestVersion: { version: "1.0.0" }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.get_skill(slug: "my-skill")
      expect(result["skill"]["slug"]).to eq("my-skill")
      expect(result["latestVersion"]["version"]).to eq("1.0.0")
    end

    it "raises ApiError on 404" do
      stub_request(:get, "#{base_url}/api/v1/skills/nonexistent")
        .to_return(status: 404, body: "Not Found")

      expect { client.get_skill(slug: "nonexistent") }.to raise_error(ClawHub::ApiError, /404/)
    end
  end

  describe "#get_skill_file" do
    it "fetches raw file content" do
      stub_request(:get, "#{base_url}/api/v1/skills/my-skill/file")
        .with(query: { path: "my-skill.SKILL.md" })
        .to_return(status: 200, body: "---\nname: My Skill\n---\nContent here")

      result = client.get_skill_file(slug: "my-skill", path: "my-skill.SKILL.md")
      expect(result).to include("My Skill")
    end

    it "passes version param" do
      stub_request(:get, "#{base_url}/api/v1/skills/my-skill/file")
        .with(query: { path: "my-skill.SKILL.md", version: "1.0.0" })
        .to_return(status: 200, body: "content")

      result = client.get_skill_file(slug: "my-skill", path: "my-skill.SKILL.md", version: "1.0.0")
      expect(result).to eq("content")
    end
  end

  describe "#download_zip" do
    it "downloads zip bytes" do
      stub_request(:get, "#{base_url}/api/v1/download")
        .with(query: { slug: "my-skill" })
        .to_return(status: 200, body: "ZIPDATA")

      result = client.download_zip(slug: "my-skill")
      expect(result).to eq("ZIPDATA")
    end
  end
end
