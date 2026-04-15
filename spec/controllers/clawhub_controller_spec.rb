# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClawhubController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:client) { instance_double(ClawHub::Client) }

  before do
    sign_in user
    allow(ClawHub::Client).to receive(:new).and_return(client)
  end

  # Writes pending install data directly into Rails.cache using the same key
  # the controller derives from session.id, so tests don't depend on cookie storage.
  def set_pending_install(data)
    # Trigger a request so the session gets an ID assigned, then derive the key.
    request.session # ensure session exists
    session_id = request.session.id || request.session_options[:id]
    Rails.cache.write("clawhub:pending_install:#{session_id}", data)
  end

  describe "GET #index" do
    it "lists trending skills by default" do
      allow(client).to receive(:list_skills)
        .with(sort: "trending", cursor: nil)
        .and_return({ "items" => [{ "slug" => "skill-1", "displayName" => "Skill 1" }], "nextCursor" => nil })

      get :index
      expect(response).to have_http_status(:ok)
      expect(assigns(:skills)).to be_an(Array)
      expect(assigns(:sort)).to eq("trending")
    end

    it "searches when q param present" do
      allow(client).to receive(:search_skills)
        .with(query: "coding", limit: 20)
        .and_return({ "results" => [{ "slug" => "coding-helper" }] })

      get :index, params: { q: "coding" }
      expect(response).to have_http_status(:ok)
      expect(assigns(:skills).first["slug"]).to eq("coding-helper")
    end

    it "supports sort parameter" do
      allow(client).to receive(:list_skills)
        .with(sort: "popular", cursor: nil)
        .and_return({ "items" => [], "nextCursor" => nil })

      get :index, params: { sort: "popular" }
      expect(assigns(:sort)).to eq("popular")
    end

    it "handles API errors gracefully" do
      allow(client).to receive(:list_skills).and_raise(ClawHub::ApiError.new("timeout", status: 504))

      get :index
      expect(response).to have_http_status(:ok)
      expect(assigns(:skills)).to eq([])
      expect(assigns(:error)).to include("timeout")
    end
  end

  describe "GET #show" do
    it "shows skill detail" do
      allow(client).to receive(:get_skill).with(slug: "my-skill").and_return({
        "skill" => { "slug" => "my-skill", "displayName" => "My Skill", "stats" => {} },
        "latestVersion" => { "version" => "1.0.0" }
      })

      get :show, params: { slug: "my-skill" }
      expect(response).to have_http_status(:ok)
      expect(assigns(:skill_data)["skill"]["slug"]).to eq("my-skill")
    end

    it "detects installed skills" do
      create(:skill, name: "My Skill", source: "clawhub", source_url: "https://clawhub.ai/skills/my-skill")

      allow(client).to receive(:get_skill).with(slug: "my-skill").and_return({
        "skill" => { "slug" => "my-skill", "displayName" => "My Skill", "stats" => {} },
        "latestVersion" => {}
      })

      get :show, params: { slug: "my-skill" }
      expect(assigns(:installed)).to be true
    end

    it "redirects on API error" do
      allow(client).to receive(:get_skill).and_raise(ClawHub::ApiError.new("Not found", status: 404))

      get :show, params: { slug: "nonexistent" }
      expect(response).to redirect_to(clawhub_index_path)
      expect(flash[:alert]).to include("Could not load skill")
    end
  end

  describe "POST #install" do
    context "when install succeeds (clean)" do
      let(:skill) { create(:skill, name: "Test Skill", source: "clawhub") }

      before do
        allow(ClawHub::SkillInstaller).to receive(:call).and_return(
          ServiceResponse.success(data: { skill: skill, scan_result: {}, status: "installed" })
        )
      end

      it "redirects to skill page" do
        post :install, params: { slug: "test-skill" }
        expect(response).to redirect_to(skill_path(skill))
        expect(flash[:notice]).to include("installed from ClawHub")
      end
    end

    context "when install requires review" do
      before do
        allow(ClawHub::SkillInstaller).to receive(:call).and_return(
          ServiceResponse.success(data: {
            skill: nil,
            scan_result: { status: "flagged" },
            status: "pending_review",
            pending_attributes: { name: "Test", source: "clawhub", source_url: "https://clawhub.ai/skills/test-skill" }
          })
        )
      end

      it "stores pending install in cache and redirects to review" do
        post :install, params: { slug: "test-skill" }
        expect(response).to redirect_to(review_clawhub_index_path)

        # Verify data landed in Rails.cache, not the cookie session
        cache_key = "clawhub:pending_install:#{request.session.id}"
        cached = Rails.cache.read(cache_key)
        expect(cached).to be_present
        expect(cached[:slug]).to eq("test-skill")
        expect(session[:pending_clawhub_install]).to be_nil
      end
    end

    context "when install is blocked" do
      before do
        allow(ClawHub::SkillInstaller).to receive(:call).and_return(
          ServiceResponse.success(data: { skill: nil, scan_result: {}, status: "blocked" })
        )
      end

      it "redirects back with alert" do
        post :install, params: { slug: "test-skill" }
        expect(response).to redirect_to(clawhub_path(slug: "test-skill"))
        expect(flash[:alert]).to include("blocked")
      end
    end

    context "when install fails" do
      before do
        allow(ClawHub::SkillInstaller).to receive(:call).and_return(
          ServiceResponse.failure(error: "API error")
        )
      end

      it "redirects with error" do
        post :install, params: { slug: "test-skill" }
        expect(response).to redirect_to(clawhub_path(slug: "test-skill"))
        expect(flash[:alert]).to eq("API error")
      end
    end
  end

  describe "GET #review" do
    it "renders review page when pending install exists" do
      set_pending_install(
        slug: "test-skill",
        scan_result: { status: "flagged", findings: [] },
        pending_attributes: { name: "Test Skill", summary: "A test" }
      )

      get :review
      expect(response).to have_http_status(:ok)
      expect(assigns(:scan_result)).to be_present
    end

    it "redirects when no pending install" do
      get :review
      expect(response).to redirect_to(clawhub_index_path)
    end
  end

  describe "POST #confirm" do
    context "with pending install" do
      before do
        set_pending_install(
          slug: "test-skill",
          scan_result: { status: "flagged", findings: [] },
          pending_attributes: {
            name: "Test Skill",
            description: "Desc",
            summary: "A test skill",
            content: "Do things",
            category: "coding",
            source: "clawhub",
            source_url: "https://clawhub.ai/skills/test-skill"
          }
        )
      end

      it "creates the skill and clears cache" do
        expect { post :confirm, params: { slug: "test-skill" } }.to change(Skill, :count).by(1)

        cache_key = "clawhub:pending_install:#{request.session.id}"
        expect(Rails.cache.read(cache_key)).to be_nil
        expect(response).to redirect_to(skill_path(Skill.last))
        expect(Skill.last.source).to eq("clawhub")
        expect(Skill.last.approved_by).to eq(user.id)
      end
    end

    context "without pending install" do
      it "redirects with alert" do
        post :confirm, params: { slug: "test-skill" }
        expect(response).to redirect_to(clawhub_index_path)
        expect(flash[:alert]).to include("No pending install")
      end
    end

    context "with blocked scan result" do
      before do
        set_pending_install(
          slug: "test-skill",
          scan_result: { status: "blocked" },
          pending_attributes: { name: "Bad Skill" }
        )
      end

      it "rejects blocked skills" do
        post :confirm, params: { slug: "test-skill" }
        expect(response).to redirect_to(clawhub_index_path)
        expect(flash[:alert]).to include("Blocked")
      end
    end
  end
end
