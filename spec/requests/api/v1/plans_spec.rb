# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::Plans", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

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
        expect(json["path"]).to include("/workspace/plans/")
      end

      it "saves file to workspace/plans directory" do
        post "/api/v1/plans/save", params: params

        # Check if file was created
        filepath = "/workspace/plans/test-plan.md"
        expect(File.exist?(filepath)).to be true

        # Clean up
        File.delete(filepath) if File.exist?(filepath)
      end

      it "writes correct content to file" do
        post "/api/v1/plans/save", params: params

        filepath = "/workspace/plans/test-plan.md"
        content = File.read(filepath)
        expect(content).to eq("# Plan Summary\nTest content")

        # Clean up
        File.delete(filepath) if File.exist?(filepath)
      end
    end

    context "with missing filename" do
      let(:params) do
        {
          content: "# Plan",
          location: "workspace"
        }
      end

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
      let(:params) do
        {
          filename: "test-plan.md",
          location: "workspace"
        }
      end

      it "returns error" do
        post "/api/v1/plans/save", params: params

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with invalid location" do
      let(:params) do
        {
          filename: "test-plan.md",
          content: "# Plan",
          location: "invalid"
        }
      end

      it "returns error" do
        post "/api/v1/plans/save", params: params

        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["error"]).to include("Invalid location")
      end
    end

    context "with special characters in filename" do
      let(:params) do
        {
          filename: "test-plan<>|*.md",
          content: "# Plan",
          location: "workspace"
        }
      end

      it "sanitizes filename" do
        post "/api/v1/plans/save", params: params

        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        # Special characters should be replaced
        expect(json["filename"]).not_to include("<")
        expect(json["filename"]).not_to include(">")
      end
    end

    context "when not authenticated" do
      before { sign_out user }

      it "returns unauthorized" do
        post "/api/v1/plans/save", params: params

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "plans directory creation" do
    let(:params) do
      {
        filename: "test.md",
        content: "content",
        location: "workspace"
      }
    end

    it "creates plans directory if it doesn't exist" do
      # Ensure directory doesn't exist
      plans_dir = "/workspace/plans"
      FileUtils.rm_rf(plans_dir) if Dir.exist?(plans_dir)

      post "/api/v1/plans/save", params: params

      expect(Dir.exist?("/workspace/plans")).to be true

      # Clean up
      FileUtils.rm_rf("/workspace/plans") if Dir.exist?("/workspace/plans")
    end
  end
end
