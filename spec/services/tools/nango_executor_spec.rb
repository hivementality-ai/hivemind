# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::NangoExecutor do
  let(:agent) { create(:agent) }

  def stub_vault(pairs)
    allow(VaultEntry).to receive(:find_by) do |namespace:, key:|
      val = pairs[[ namespace, key ]]
      val && double(value: val)
    end
  end

  def execute(input)
    described_class.new(input: input, config: {}, agent: agent).call
  end

  before { stub_vault({ [ "nango", "secret_key" ] => "sk_test" }) }

  it "fails when the secret key is not configured" do
    stub_vault({})
    result = execute("action" => "proxy")
    expect(result.success?).to be(false)
    expect(result.error).to include("secret key not configured")
  end

  it "requires proxy identifiers" do
    result = execute("action" => "proxy", "endpoint" => "/me")
    expect(result.success?).to be(false)
    expect(result.error).to include("connection_id")
  end

  it "proxies a request with Nango auth headers" do
    stub = stub_request(:get, "https://api.nango.dev/proxy/repos/acme/app/issues")
      .with(headers: {
        "Authorization" => "Bearer sk_test",
        "Connection-Id" => "conn_1",
        "Provider-Config-Key" => "github"
      })
      .to_return(status: 200, body: [ { number: 1 } ].to_json)

    result = execute(
      "action" => "proxy", "endpoint" => "/repos/acme/app/issues",
      "connection_id" => "conn_1", "provider_config_key" => "github"
    )

    expect(result.success?).to be(true)
    expect(result.data[:output]).to include("\"number\"")
    expect(stub).to have_been_requested
  end

  it "surfaces HTTP errors" do
    stub_request(:get, "https://api.nango.dev/connection")
      .to_return(status: 401, body: { error: "bad key" }.to_json)

    result = execute("action" => "list_connections")
    expect(result.success?).to be(false)
    expect(result.error).to include("HTTP 401")
  end

  it "honors a self-hosted host override" do
    stub_vault({ [ "nango", "secret_key" ] => "sk_test", [ "nango", "host" ] => "https://nango.internal" })
    stub = stub_request(:get, "https://nango.internal/config").to_return(status: 200, body: "[]")

    execute("action" => "list_integrations")
    expect(stub).to have_been_requested
  end
end
