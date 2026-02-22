# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::Plans", type: :request do
  let(:user) { create(:user) }
  let(:tmp_workspace) { Dir.mktmpdir("workspace") }
  let(:plans_dir) { File.join(tmp_workspace, "plans") }

  before do
    sign_in user
    # Stub the controller's save_to_workspace to use temp dir
    allow_any_instance_of(Api::V1::PlansController).to receive(:save_to_workspace).and_wrap_original do |method, filename, content|
      safe_filename = File.basename(filename).gsub(/[^a-zA-Z0-9._-]/, "_")
      FileUtils.mkdir_p(plans_dir)
      filepath = File.join(plans_dir, safe_filename)
      File.write(filepath, content)
      {
        success: true,
        message: "Plan summary saved",
        filename: safe_filename,
        path: filepath
      }
    end
  end

  after do
    FileUtils.rm_rf(tmp_workspace)
  end

  describe "POST /api/v1/plans/save" do
    let(:params) do
      {
        filename: "test-plan.md",
        content: "# Plan Summary\nTest content",
        location: "workspace"
      }
    end

    context "with valid parameters" do
      it "returns success response" do
        post "/api/v1/plans/save", params: params

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
      end

      it "includes filename in response" do
        post "/api/v1/plans/save", params: params

        json = JSON.parse(response.body)
        expect(json["filename"]).to eq("test-plan.md")
      end

      it "includes path in response" do
        post "/api/v1/plans/save", params: params

        json = JSON.parse(response.body)
        expect(json["path"]).to include("plans/")
      end

      it "saves file to plans directory" do
        post "/api/v1/plans/save", params: params

        filepath = File.join(plans_dir, "test-plan.md")
        expect(File.exist?(filepath)).to be true
      end

      it "writes correct content to file" do
        post "/api/v1/plans/save", params: params

        filepath = File.join(plans_dir, "test-plan.md")
        content = File.read(filepath)
        expect(content).to eq("# Plan Summary\nTest content")
      end
    end

    context "with missing filename" do
      let(:params) { { content: "# Plan", location: "workspace" } }

      it "returns unprocessable entity status" do
        post "/api/v1/plans/save", params: params
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns error message" do
        post "/api/v1/plans/save", params: params
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["error"]).to include("required")
      end
    end

    context "with missing content" do
      let(:params) { { filename: "test-plan.md", location: "workspace" } }

      it "returns error" do
        post "/api/v1/plans/save", params: params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with invalid location" do
      let(:params) { { filename: "test-plan.md", content: "# Plan", location: "invalid" } }

      it "returns error" do
        post "/api/v1/plans/save", params: params
        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["error"]).to include("Invalid location")
      end
    end

    context "with special characters in filename" do
      let(:params) { { filename: "test-plan<>|*.md", content: "# Plan", location: "workspace" } }

      it "sanitizes filename" do
        post "/api/v1/plans/save", params: params
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["filename"]).not_to include("<")
        expect(json["filename"]).not_to include(">")
      end
    end

    context "when not authenticated" do
      before { sign_out user }

      it "redirects to sign in" do
        post "/api/v1/plans/save", params: params
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "plans directory creation" do
    let(:params) { { filename: "test.md", content: "content", location: "workspace" } }

    it "creates plans directory if it doesn't exist" do
      expect(Dir.exist?(plans_dir)).to be false

      post "/api/v1/plans/save", params: params

      expect(Dir.exist?(plans_dir)).to be true
    end
  end
end
