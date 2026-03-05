# frozen_string_literal: true

require "rails_helper"

RSpec.describe MigrationController, type: :controller do
  let(:user) { create(:user, :owner) }
  let(:workspace_path) { "/app/agents-shared/test-config" }
  let(:agent) { create(:agent) }

  let(:mock_report) do
    report = OpenClaw::MigrationReport.new(workspace_path: workspace_path)
    report.agent = agent
    report.identity_imported = true
    report.memories_created = 3
    report.memory_files_processed = 2
    report.skills_imported = [ { name: "greeting" } ]
    report.skills_skipped = []
    report.skill_scan_results = [ { name: "greeting", status: "clean" } ]
    report.channels_created = [ { name: "slack-main" } ]
    report.channels_skipped = []
    report.sessions_created = 5
    report.tools_created = [ { name: "web_search" } ]
    report.tools_skipped = []
    report.markers_found = [ "SOUL.md", "config.json" ]
    report
  end

  before { sign_in user }

  describe "GET #upload" do
    it "renders the upload form" do
      get :upload
      expect(response).to be_successful
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to sign in" do
        get :upload
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "POST #scan" do
    context "with valid path" do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(workspace_path).and_return(true)
        allow(OpenClaw::Migrator).to receive(:call)
          .with(workspace_path: workspace_path, agent_slug: nil, dry_run: true)
          .and_return(ServiceResponse.success(data: { report: mock_report }))
      end

      it "stores report in session and renders scan" do
        post :scan, params: { workspace_path: workspace_path }
        expect(response).to be_successful
        expect(session[:pending_migration]).to be_present
        expect(session[:pending_migration][:workspace_path]).to eq(workspace_path)
      end

      it "passes agent_slug when provided" do
        allow(OpenClaw::Migrator).to receive(:call)
          .with(workspace_path: workspace_path, agent_slug: "my-bot", dry_run: true)
          .and_return(ServiceResponse.success(data: { report: mock_report }))

        post :scan, params: { workspace_path: workspace_path, agent_slug: "my-bot" }
        expect(response).to be_successful
      end
    end

    context "with invalid path" do
      it "redirects to migration with alert" do
        post :scan, params: { workspace_path: "/nonexistent/path" }
        expect(response).to redirect_to(migration_path)
        expect(flash[:alert]).to match(/Invalid path/)
      end
    end

    context "with blank path" do
      it "redirects to migration with alert" do
        post :scan, params: { workspace_path: "" }
        expect(response).to redirect_to(migration_path)
        expect(flash[:alert]).to match(/Invalid path/)
      end
    end

    context "when migrator fails" do
      before do
        allow(File).to receive(:directory?).and_call_original
        allow(File).to receive(:directory?).with(workspace_path).and_return(true)
        allow(OpenClaw::Migrator).to receive(:call)
          .and_return(ServiceResponse.failure(error: "Missing config.json"))
      end

      it "redirects to migration with alert" do
        post :scan, params: { workspace_path: workspace_path }
        expect(response).to redirect_to(migration_path)
        expect(flash[:alert]).to match(/Scan failed/)
      end
    end
  end

  describe "GET #review" do
    context "with pending migration in session" do
      before do
        session[:pending_migration] = {
          workspace_path: workspace_path,
          agent_slug: nil,
          report: mock_report.to_h
        }
      end

      it "renders the review page" do
        get :review
        expect(response).to be_successful
      end
    end

    context "without pending migration" do
      it "redirects to migration" do
        get :review
        expect(response).to redirect_to(migration_path)
        expect(flash[:alert]).to match(/No pending migration/)
      end
    end
  end

  describe "POST #run_import" do
    context "with pending migration in session" do
      before do
        session[:pending_migration] = {
          workspace_path: workspace_path,
          agent_slug: nil,
          report: mock_report.to_h
        }
        allow(OpenClaw::Migrator).to receive(:call)
          .with(workspace_path: workspace_path, agent_slug: nil, dry_run: false)
          .and_return(ServiceResponse.success(data: { report: mock_report }))
      end

      it "runs the real migration and redirects to reconnect" do
        post :run_import
        expect(response).to redirect_to(migration_reconnect_path)
        expect(session[:migration_result]).to be_present
        expect(session[:pending_migration]).to be_nil
      end
    end

    context "without pending migration" do
      it "redirects to migration" do
        post :run_import
        expect(response).to redirect_to(migration_path)
      end
    end

    context "when migrator fails" do
      before do
        session[:pending_migration] = {
          workspace_path: workspace_path,
          agent_slug: nil,
          report: mock_report.to_h
        }
        allow(OpenClaw::Migrator).to receive(:call)
          .and_return(ServiceResponse.failure(error: "Import error"))
      end

      it "redirects to review with alert" do
        post :run_import
        expect(response).to redirect_to(migration_review_path)
        expect(flash[:alert]).to match(/Import failed/)
      end
    end
  end

  describe "GET #reconnect" do
    context "with migration result in session" do
      before do
        session[:migration_result] = mock_report.to_h
      end

      it "renders the reconnect page" do
        get :reconnect
        expect(response).to be_successful
      end

      it "clears the session after render" do
        get :reconnect
        expect(session[:migration_result]).to be_nil
      end
    end

    context "without migration result" do
      it "redirects to migration" do
        get :reconnect
        expect(response).to redirect_to(migration_path)
        expect(flash[:alert]).to match(/No migration result/)
      end
    end
  end
end
