# frozen_string_literal: true

require "rails_helper"

RSpec.describe Swarms::Deployers::ApiIntegrationsDeployer do
  def build_document(api_integrations: [])
    Swarms::SwarmDocument.new(
      swarm_version:    "1.0",
      name:             "Test Swarm",
      api_integrations: api_integrations
    )
  end

  # ---------------------------------------------------------------------------
  # Result contract
  # ---------------------------------------------------------------------------

  describe "result contract" do
    it "always returns a successful ServiceResponse" do
      result = described_class.call(document: build_document)
      expect(result).to be_success
    end

    it "returns an empty api_integrations array when the document has none" do
      result = described_class.call(document: build_document(api_integrations: []))
      expect(result.payload[:api_integrations]).to eq([])
    end

    it "returns one DeployResult per integration in the document" do
      doc = build_document(api_integrations: [
        { "name" => "api-a", "base_url" => "https://api-a.example.com" },
        { "name" => "api-b", "base_url" => "https://api-b.example.com" }
      ])
      result = described_class.call(document: doc)
      expect(result.payload[:api_integrations].size).to eq(2)
    end
  end

  # ---------------------------------------------------------------------------
  # No conflict — create
  # ---------------------------------------------------------------------------

  describe "when no platform API integration exists with that name" do
    it "creates a new ApiIntegration record" do
      doc = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://api.example.com" }])
      expect { described_class.call(document: doc) }.to change(ApiIntegration, :count).by(1)
    end

    it "returns action :created" do
      doc    = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://api.example.com" }])
      result = described_class.call(document: doc)
      expect(result.payload[:api_integrations].first.action).to eq(:created)
    end

    it "stores all provided attributes" do
      doc = build_document(api_integrations: [{
        "name"            => "my-api",
        "base_url"        => "https://api.example.com",
        "description"     => "My API",
        "auth_config"     => { "type" => "bearer", "vault_key" => "vault:swarm_export/token" },
        "default_headers" => { "X-Custom" => "value" },
        "timeout_seconds" => 60
      }])
      result      = described_class.call(document: doc)
      integration = result.payload[:api_integrations].first.record

      expect(integration.base_url).to eq("https://api.example.com")
      expect(integration.description).to eq("My API")
      expect(integration.auth_config["type"]).to eq("bearer")
      expect(integration.default_headers["X-Custom"]).to eq("value")
      expect(integration.timeout_seconds).to eq(60)
    end

    it "stores endpoints when provided" do
      doc = build_document(api_integrations: [{
        "name"      => "my-api",
        "base_url"  => "https://api.example.com",
        "endpoints" => [{ "method" => "GET", "path" => "/users", "summary" => "List users" }]
      }])
      integration = described_class.call(document: doc).payload[:api_integrations].first.record
      expect(integration.endpoints.first["path"]).to eq("/users")
    end

    it "defaults enabled to true when not specified" do
      doc         = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://api.example.com" }])
      integration = described_class.call(document: doc).payload[:api_integrations].first.record
      expect(integration.enabled).to be true
    end

    it "respects an explicit enabled: false" do
      doc         = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://api.example.com", "enabled" => false }])
      integration = described_class.call(document: doc).payload[:api_integrations].first.record
      expect(integration.enabled).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — no resolution (default skip)
  # ---------------------------------------------------------------------------

  describe "when an integration already exists and no resolution is provided" do
    let!(:existing) { ApiIntegration.create!(name: "my-api", base_url: "https://old.example.com") }

    it "does not create a new ApiIntegration record" do
      doc = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://new.example.com" }])
      expect { described_class.call(document: doc) }.not_to change(ApiIntegration, :count)
    end

    it "returns action :skipped" do
      doc    = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://new.example.com" }])
      result = described_class.call(document: doc)
      expect(result.payload[:api_integrations].first.action).to eq(:skipped)
    end

    it "leaves the existing record unchanged" do
      doc = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://new.example.com" }])
      described_class.call(document: doc)
      expect(existing.reload.base_url).to eq("https://old.example.com")
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — :overwrite resolution
  # ---------------------------------------------------------------------------

  describe "resolution :overwrite" do
    let!(:existing) { ApiIntegration.create!(name: "my-api", base_url: "https://old.example.com") }

    it "updates the existing record and returns :updated" do
      doc    = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://new.example.com" }])
      result = described_class.call(document: doc, resolutions: { "my-api" => :overwrite })
      expect(result.payload[:api_integrations].first.action).to eq(:updated)
      expect(existing.reload.base_url).to eq("https://new.example.com")
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict — :rename resolution
  # ---------------------------------------------------------------------------

  describe "resolution :rename" do
    let!(:existing) { ApiIntegration.create!(name: "my-api", base_url: "https://old.example.com") }

    it "creates a new ApiIntegration with a suffixed name and returns :renamed" do
      doc    = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://new.example.com" }])
      result = described_class.call(document: doc, resolutions: { "my-api" => :rename })
      dr     = result.payload[:api_integrations].first
      expect(dr.action).to eq(:renamed)
      expect(dr.name).to eq("my-api-2")
      expect(dr.record.base_url).to eq("https://new.example.com")
    end

    it "increments the suffix when -2 is also taken" do
      ApiIntegration.create!(name: "my-api-2", base_url: "https://other.example.com")
      doc    = build_document(api_integrations: [{ "name" => "my-api", "base_url" => "https://new.example.com" }])
      result = described_class.call(document: doc, resolutions: { "my-api" => :rename })
      expect(result.payload[:api_integrations].first.name).to eq("my-api-3")
    end
  end
end
