# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Serializers::ApiIntegrationSerializer do
  def build_integration(attrs = {})
    ApiIntegration.new({
      name:     "my-api",
      base_url: "https://api.example.com",
      enabled:  true
    }.merge(attrs))
  end

  describe "#call" do
    it "returns a hash with required fields" do
      integration = build_integration
      result      = described_class.call(api_integration: integration)

      expect(result["name"]).to eq("my-api")
      expect(result["base_url"]).to eq("https://api.example.com")
    end

    it "includes description when present" do
      integration = build_integration(description: "My API integration")
      result      = described_class.call(api_integration: integration)
      expect(result["description"]).to eq("My API integration")
    end

    it "omits description when blank" do
      integration = build_integration(description: nil)
      result      = described_class.call(api_integration: integration)
      expect(result).not_to have_key("description")
    end

    it "includes auth_config when present" do
      integration = build_integration(auth_config: { "type" => "bearer", "vault_key" => "vault:swarm_export/token" })
      result      = described_class.call(api_integration: integration)
      expect(result["auth_config"]["type"]).to eq("bearer")
    end

    it "omits auth_config when empty" do
      integration = build_integration(auth_config: {})
      result      = described_class.call(api_integration: integration)
      expect(result).not_to have_key("auth_config")
    end

    it "includes default_headers when present" do
      integration = build_integration(default_headers: { "X-Custom" => "value" })
      result      = described_class.call(api_integration: integration)
      expect(result["default_headers"]["X-Custom"]).to eq("value")
    end

    it "includes endpoints when present" do
      integration = build_integration(endpoints: [{ "method" => "GET", "path" => "/users" }])
      result      = described_class.call(api_integration: integration)
      expect(result["endpoints"].first["path"]).to eq("/users")
    end

    it "omits endpoints when empty" do
      integration = build_integration(endpoints: [])
      result      = described_class.call(api_integration: integration)
      expect(result).not_to have_key("endpoints")
    end

    it "includes spec_format when present" do
      integration = build_integration(spec_format: "openapi")
      result      = described_class.call(api_integration: integration)
      expect(result["spec_format"]).to eq("openapi")
    end

    it "includes spec_data when present" do
      integration = build_integration(spec_data: { "openapi" => "3.0.0" })
      result      = described_class.call(api_integration: integration)
      expect(result["spec_data"]["openapi"]).to eq("3.0.0")
    end

    it "includes timeout_seconds when set" do
      integration = build_integration(timeout_seconds: 60)
      result      = described_class.call(api_integration: integration)
      expect(result["timeout_seconds"]).to eq(60)
    end

    it "includes max_response_bytes when set" do
      integration = build_integration(max_response_bytes: 2_097_152)
      result      = described_class.call(api_integration: integration)
      expect(result["max_response_bytes"]).to eq(2_097_152)
    end

    it "includes enabled when set" do
      integration = build_integration(enabled: false)
      result      = described_class.call(api_integration: integration)
      expect(result["enabled"]).to be false
    end
  end
end
