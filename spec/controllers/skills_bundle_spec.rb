# frozen_string_literal: true

require "rails_helper"

RSpec.describe SkillsController, "skill bundles", type: :controller do
  let(:user) { create(:user, :owner) }

  before { sign_in user }

  describe "GET #export_bundle" do
    let!(:skill) { create(:skill, name: "shareable-skill", builtin: false, content: "Do a useful thing.") }

    it "returns a JSON bundle containing the skill as SKILL.md" do
      get :export_bundle
      expect(response).to be_successful
      body = JSON.parse(response.body)
      expect(body["format"]).to eq("hivemind-skill-bundle")
      names = body["skills"].map { |s| s["name"] }
      expect(names).to include("shareable-skill")
      expect(body["skills"].first["skill_md"]).to include("name: shareable-skill")
    end
  end

  describe "POST #import_bundle" do
    let(:bundle) do
      {
        format: "hivemind-skill-bundle",
        version: "1",
        skills: [
          { name: "imported-skill",
            skill_md: "---\nname: imported-skill\ndescription: From a bundle\ntags: [ops]\n---\nRun the steps." }
        ]
      }
    end
    let(:file) do
      Rack::Test::UploadedFile.new(StringIO.new(bundle.to_json), "application/json", original_filename: "bundle.json")
    end

    it "imports skills from the bundle" do
      expect { post :import_bundle, params: { file: file } }.to change(Skill, :count).by(1)
      imported = Skill.find_by(name: "imported-skill")
      expect(imported.tags).to eq(%w[ops])
      expect(imported.source).to eq("import")
    end

    it "redirects with an invalid-bundle alert for non-JSON" do
      bad = Rack::Test::UploadedFile.new(StringIO.new("not json"), "application/json", original_filename: "x.json")
      post :import_bundle, params: { file: bad }
      expect(flash[:alert]).to match(/Invalid bundle/)
    end
  end
end
