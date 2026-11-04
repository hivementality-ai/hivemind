# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connector do
  subject(:connector) { build(:connector) }

  def operation(overrides = {})
    {
      "name" => "ping", "description" => "Ping", "method" => "GET", "path" => "/ping",
      "params" => { "type" => "object", "properties" => {} }, "read_only" => true
    }.merge(overrides)
  end

  it "is valid by default" do
    expect(connector).to be_valid
  end

  describe "slug" do
    it "must be unique" do
      create(:connector, slug: "acme")
      expect(build(:connector, slug: "acme")).not_to be_valid
    end

    it "rejects characters that would break the tool name" do
      expect(build(:connector, slug: "Acme Co")).not_to be_valid
      expect(build(:connector, slug: "acme__co")).not_to be_valid
    end
  end

  describe "base_url" do
    it "accepts https" do
      expect(build(:connector, base_url: "https://api.example.com")).to be_valid
    end

    it "rejects plain http to a public host" do
      connector.base_url = "http://api.example.com"
      expect(connector).not_to be_valid
      expect(connector.errors[:base_url].join).to include("https")
    end

    it "allows http on loopback and the local network" do
      %w[http://localhost:3000 http://127.0.0.1:8080 http://192.168.1.20 http://10.0.0.5 http://nas.local].each do |url|
        expect(build(:connector, base_url: url)).to be_valid, url
      end
    end

    it "rejects other schemes, credentials, queries and cloud metadata hosts" do
      [ "ftp://example.com", "https://user:pw@example.com", "https://example.com/?a=1",
        "http://169.254.169.254/latest", "https://metadata.google.internal" ].each do |url|
        expect(build(:connector, base_url: url)).not_to be_valid, url
      end
    end
  end

  describe "auth_config" do
    it "accepts vault references" do
      connector.assign_attributes(auth_scheme: "bearer", auth_config: { "secret" => "vault:widgets/token" })
      expect(connector).to be_valid
    end

    it "rejects a raw secret without echoing it" do
      connector.assign_attributes(auth_scheme: "bearer", auth_config: { "secret" => "sk-live-abcdef123456" })
      expect(connector).not_to be_valid
      expect(connector.errors.full_messages.join).to include("vault reference")
      expect(connector.errors.full_messages.join).not_to include("sk-live-abcdef123456")
    end

    it "rejects a raw secret in any slot of a multi-secret scheme" do
      connector.assign_attributes(auth_scheme: "basic", auth_config: { "username" => "vault:a/user", "password" => "hunter2" })
      expect(connector).not_to be_valid
    end

    it "requires the keys its scheme needs" do
      connector.assign_attributes(auth_scheme: "api_key_header", auth_config: { "secret" => "vault:a/k" })
      expect(connector).not_to be_valid
      connector.auth_config = { "header_name" => "X-Api-Key", "secret" => "vault:a/k" }
      expect(connector).to be_valid
    end

    it "rejects unexpected keys and config on a none scheme" do
      connector.auth_config = { "secret" => "vault:a/k" }
      expect(connector).not_to be_valid
    end

    it "rejects an unknown scheme" do
      connector.auth_scheme = "magic"
      expect(connector).not_to be_valid
    end
  end

  describe "operations" do
    it "requires unique names" do
      connector.operations = [ operation, operation ]
      expect(connector).not_to be_valid
      expect(connector.errors[:operations].join).to include("unique")
    end

    it "rejects paths that escape the base URL" do
      [ "/../admin", "/a/../../b", "//evil.test/x", "/a/%2e%2e/b", "/a?x=1", "https://evil.test/x", "/a/%2Fb", "ping" ].each do |path|
        connector.operations = [ operation("path" => path) ]
        expect(connector).not_to be_valid, path
      end
    end

    it "requires placeholders to be declared params" do
      connector.operations = [ operation("path" => "/things/{id}") ]
      expect(connector).not_to be_valid
    end

    it "requires a supported method, a description and a boolean read_only" do
      expect(build(:connector, operations: [ operation("method" => "TRACE") ])).not_to be_valid
      expect(build(:connector, operations: [ operation("description" => "") ])).not_to be_valid
      expect(build(:connector, operations: [ operation("read_only" => "yes") ])).not_to be_valid
    end

    it "finds an operation by name" do
      expect(connector.operation("get_widget")["path"]).to eq("/widgets/{id}")
      expect(connector.operation("nope")).to be_nil
    end
  end

  describe "deleting" do
    it "removes the exclusions that hide it from agents" do
      connector = create(:connector)
      create(:agent_connector_exclusion, connector: connector)

      expect { connector.destroy! }.to change(AgentConnectorExclusion, :count).by(-1)
    end
  end
end
