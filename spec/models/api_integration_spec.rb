# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiIntegration, type: :model do
  subject { build(:api_integration) }

  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:name) }
    it { should validate_presence_of(:base_url) }

    it "rejects invalid base_url" do
      subject.base_url = "not-a-url"
      expect(subject).not_to be_valid
      expect(subject.errors[:base_url]).to be_present
    end

    it "accepts http urls" do
      subject.base_url = "http://example.com/api"
      expect(subject).to be_valid
    end

    it "accepts https urls" do
      subject.base_url = "https://api.example.com"
      expect(subject).to be_valid
    end
  end

  describe "associations" do
    it { should belong_to(:user).optional }
  end

  describe "scopes" do
    let!(:enabled) { create(:api_integration, enabled: true) }
    let!(:disabled) { create(:api_integration, enabled: false) }

    it ".enabled returns only enabled integrations" do
      expect(ApiIntegration.enabled).to eq([enabled])
    end
  end

  describe "#auth_type" do
    it "returns 'none' by default" do
      expect(subject.auth_type).to eq("none")
    end

    it "returns configured type" do
      subject.auth_config = { "type" => "bearer" }
      expect(subject.auth_type).to eq("bearer")
    end
  end

  describe "#api_key" do
    it "resolves key from vault" do
      subject.name = "my-api"
      subject.auth_config = {}
      create(:vault_entry, namespace: "api_integrations", key: "my-api_api_key", value: "secret123")
      expect(subject.api_key).to eq("secret123")
    end

    it "uses custom vault_key when configured" do
      subject.auth_config = { "vault_key" => "custom_key" }
      create(:vault_entry, namespace: "api_integrations", key: "custom_key", value: "custom_secret")
      expect(subject.api_key).to eq("custom_secret")
    end

    it "returns nil when no vault entry exists" do
      expect(subject.api_key).to be_nil
    end
  end

  describe "#auth_headers" do
    context "with api_key auth" do
      before do
        subject.name = "test-api"
        subject.auth_config = { "type" => "api_key" }
        create(:vault_entry, namespace: "api_integrations", key: "test-api_api_key", value: "key123")
      end

      it "returns X-API-Key header by default" do
        expect(subject.auth_headers).to eq({ "X-API-Key" => "key123" })
      end

      it "uses custom header name" do
        subject.auth_config["header_name"] = "X-Custom"
        expect(subject.auth_headers).to eq({ "X-Custom" => "key123" })
      end
    end

    context "with bearer auth" do
      before do
        subject.name = "test-api"
        subject.auth_config = { "type" => "bearer" }
        create(:vault_entry, namespace: "api_integrations", key: "test-api_api_key", value: "token123")
      end

      it "returns Authorization Bearer header" do
        expect(subject.auth_headers).to eq({ "Authorization" => "Bearer token123" })
      end
    end

    context "with basic auth" do
      before do
        subject.name = "test-api"
        subject.auth_config = { "type" => "basic", "username" => "user" }
        create(:vault_entry, namespace: "api_integrations", key: "test-api_api_key", value: "pass")
      end

      it "returns Authorization Basic header" do
        encoded = Base64.strict_encode64("user:pass")
        expect(subject.auth_headers).to eq({ "Authorization" => "Basic #{encoded}" })
      end
    end

    context "with no auth" do
      it "returns empty hash" do
        subject.auth_config = { "type" => "none" }
        expect(subject.auth_headers).to eq({})
      end
    end

    context "when api_key is nil" do
      it "returns empty hash for api_key type" do
        subject.auth_config = { "type" => "api_key" }
        expect(subject.auth_headers).to eq({})
      end

      it "returns empty hash for bearer type" do
        subject.auth_config = { "type" => "bearer" }
        expect(subject.auth_headers).to eq({})
      end
    end
  end

  describe "#request_headers" do
    it "merges default headers with auth headers" do
      subject.name = "test-api"
      subject.default_headers = { "Accept" => "application/json" }
      subject.auth_config = { "type" => "bearer" }
      create(:vault_entry, namespace: "api_integrations", key: "test-api_api_key", value: "tok")
      expect(subject.request_headers).to eq({
        "Accept" => "application/json",
        "Authorization" => "Bearer tok"
      })
    end

    it "handles nil default_headers" do
      subject.default_headers = nil
      subject.auth_config = {}
      expect(subject.request_headers).to eq({})
    end
  end

  describe "#find_endpoint" do
    before do
      subject.endpoints = [
        { "operation_id" => "getUsers", "path" => "/users", "method" => "GET", "summary" => "List users" },
        { "operation_id" => "createUser", "path" => "/users", "method" => "POST", "summary" => "Create user" }
      ]
    end

    it "finds by operation_id" do
      ep = subject.find_endpoint(operation_id: "getUsers")
      expect(ep["path"]).to eq("/users")
      expect(ep["method"]).to eq("GET")
    end

    it "finds by path and method" do
      ep = subject.find_endpoint(path: "/users", method: "post")
      expect(ep["operation_id"]).to eq("createUser")
    end

    it "returns nil when not found" do
      expect(subject.find_endpoint(operation_id: "nope")).to be_nil
    end
  end

  describe "#endpoint_summary" do
    it "returns formatted endpoint list" do
      subject.endpoints = [
        { "method" => "get", "path" => "/users", "summary" => "List users" },
        { "method" => "post", "path" => "/users", "operation_id" => "createUser" }
      ]
      summary = subject.endpoint_summary
      expect(summary).to include("GET /users — List users")
      expect(summary).to include("POST /users — createUser")
    end

    it "returns empty string for no endpoints" do
      subject.endpoints = []
      expect(subject.endpoint_summary).to eq("")
    end

    it "handles nil endpoints" do
      subject.endpoints = nil
      expect(subject.endpoint_summary).to eq("")
    end
  end
end
