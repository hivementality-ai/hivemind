# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connectors::Executor do
  let(:connector) { create(:connector) }

  before do
    allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ])
  end

  def run(operation, params = {}, conn = connector)
    described_class.call(connector: conn, operation: operation, params: params)
  end

  it "fills the path, encodes values and sends leftover params as the query on GET" do
    stub = stub_request(:get, "https://api.widgets.test/v1/widgets/a%2Fb%20c?verbose=true")
           .to_return(status: 200, body: '{"id":"a/b c"}')

    result = run("get_widget", { "id" => "a/b c", "verbose" => true })

    expect(result).to be_success
    expect(result.data[:output]).to eq('{"id":"a/b c"}')
    expect(result.data[:status]).to eq(200)
    expect(stub).to have_been_requested
  end

  it "sends params as a JSON body on POST" do
    stub = stub_request(:post, "https://api.widgets.test/v1/widgets")
           .with(body: { title: "Sprocket" }.to_json, headers: { "Content-Type" => "application/json" })
           .to_return(status: 201, body: "{}")

    expect(run("create_widget", { "title" => "Sprocket" })).to be_success
    expect(stub).to have_been_requested
  end

  it "refuses path values that would climb out of the base path" do
    result = run("get_widget", { "id" => ".." })

    expect(result).not_to be_success
    expect(result.error).to include("invalid")
  end

  it "reports missing required params without calling out" do
    result = run("get_widget", {})

    expect(result.error).to include("Missing required params: id")
    expect(a_request(:any, /widgets/)).not_to have_been_made
  end

  it "fails on an unknown operation or a disabled connector" do
    expect(run("nope").error).to include("Unknown operation")
    expect(run("get_widget", { "id" => "1" }, create(:connector, enabled: false)).error).to include("disabled")
  end

  it "returns a failure with the status for a non-2xx answer" do
    stub_request(:get, "https://api.widgets.test/v1/widgets/9").to_return(status: 404, body: "no such widget")

    result = run("get_widget", { "id" => "9" })

    expect(result).not_to be_success
    expect(result.error).to eq("HTTP 404: no such widget")
  end

  it "does not follow redirects" do
    stub_request(:get, "https://api.widgets.test/v1/widgets/9")
      .to_return(status: 302, headers: { "Location" => "http://169.254.169.254/latest" })

    expect(run("get_widget", { "id" => "9" }).error).to start_with("HTTP 302")
    expect(a_request(:get, /169\.254/)).not_to have_been_made
  end

  it "caps the response size" do
    stub_request(:get, "https://api.widgets.test/v1/widgets/9")
      .to_return(status: 200, body: "x" * (described_class::MAX_RESPONSE_BYTES + 10))

    result = run("get_widget", { "id" => "9" })

    expect(result.data[:output].bytesize).to eq(described_class::MAX_RESPONSE_BYTES)
    expect(result.data[:truncated]).to be(true)
  end

  it "turns timeouts into failures" do
    stub_request(:get, "https://api.widgets.test/v1/widgets/9").to_timeout

    expect(run("get_widget", { "id" => "9" })).not_to be_success
  end

  it "applies explicit timeouts to the connection" do
    http = instance_double(Net::HTTP, start: [ 200, "{}", false ])
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:ipaddr=)
    allow(http).to receive(:use_ssl=)
    expect(http).to receive(:open_timeout=).with(described_class::OPEN_TIMEOUT)
    expect(http).to receive(:read_timeout=).with(described_class::READ_TIMEOUT)
    expect(http).to receive(:write_timeout=).with(described_class::WRITE_TIMEOUT)

    run("get_widget", { "id" => "1" })
  end

  it "pins the connection to the address it validated" do
    http = instance_double(Net::HTTP, start: [ 200, "{}", false ])
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:write_timeout=)
    expect(http).to receive(:ipaddr=).with("93.184.216.34")

    run("get_widget", { "id" => "1" })
  end

  describe "metadata address block" do
    it "refuses a name that resolves to the metadata address" do
      allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "169.254.169.254" ])

      result = run("get_widget", { "id" => "1" })

      expect(result).not_to be_success
      expect(result.error).to include("blocked address")
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it "refuses a connector saved with a metadata base URL" do
      bad = build(:connector, base_url: "http://169.254.169.254/latest")
      bad.save(validate: false)

      result = run("get_widget", { "id" => "1" }, bad)

      expect(result.error).to include("blocked address")
      expect(a_request(:any, /169\.254/)).not_to have_been_made
    end
  end

  describe "auth injection" do
    before do
      create(:vault_entry, namespace: "widgets", key: "token", value: "tok-secret-9999")
      create(:vault_entry, namespace: "widgets", key: "user", value: "alice")
      create(:vault_entry, namespace: "widgets", key: "pass", value: "pw-secret-1")
    end

    it "sends a bearer token read from the vault" do
      conn = create(:connector, :bearer)
      stub = stub_request(:get, "https://api.widgets.test/v1/widgets/1")
             .with(headers: { "Authorization" => "Bearer tok-secret-9999" }).to_return(status: 200, body: "{}")

      expect(run("get_widget", { "id" => "1" }, conn)).to be_success
      expect(stub).to have_been_requested
    end

    it "sends an api key header" do
      conn = create(:connector, auth_scheme: "api_key_header",
                                auth_config: { "header_name" => "X-Api-Key", "secret" => "vault:widgets/token" })
      stub = stub_request(:get, "https://api.widgets.test/v1/widgets/1")
             .with(headers: { "X-Api-Key" => "tok-secret-9999" }).to_return(status: 200, body: "{}")

      run("get_widget", { "id" => "1" }, conn)
      expect(stub).to have_been_requested
    end

    it "sends an api key query parameter" do
      conn = create(:connector, auth_scheme: "api_key_query",
                                auth_config: { "param_name" => "key", "secret" => "vault:widgets/token" })
      stub = stub_request(:get, "https://api.widgets.test/v1/widgets/1?key=tok-secret-9999").to_return(status: 200, body: "{}")

      run("get_widget", { "id" => "1" }, conn)
      expect(stub).to have_been_requested
    end

    it "sends basic credentials" do
      conn = create(:connector, auth_scheme: "basic",
                                auth_config: { "username" => "vault:widgets/user", "password" => "vault:widgets/pass" })
      stub = stub_request(:get, "https://api.widgets.test/v1/widgets/1")
             .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64('alice:pw-secret-1')}" })
             .to_return(status: 200, body: "{}")

      run("get_widget", { "id" => "1" }, conn)
      expect(stub).to have_been_requested
    end

    it "sends an oauth2 access token as a bearer" do
      conn = create(:connector, auth_scheme: "oauth2", auth_config: { "access_token" => "vault:widgets/token" })
      stub = stub_request(:get, "https://api.widgets.test/v1/widgets/1")
             .with(headers: { "Authorization" => "Bearer tok-secret-9999" }).to_return(status: 200, body: "{}")

      run("get_widget", { "id" => "1" }, conn)
      expect(stub).to have_been_requested
    end

    it "fails without calling out when the vault entry is missing" do
      conn = create(:connector, auth_scheme: "bearer", auth_config: { "secret" => "vault:widgets/missing" })

      result = run("get_widget", { "id" => "1" }, conn)

      expect(result.error).to include("Secret not found")
      expect(a_request(:any, /widgets/)).not_to have_been_made
    end

    it "scrubs the secret if the API echoes it back" do
      conn = create(:connector, :bearer)
      stub_request(:get, "https://api.widgets.test/v1/widgets/1").to_return(status: 200, body: "you sent tok-secret-9999")

      expect(run("get_widget", { "id" => "1" }, conn).data[:output]).to eq("you sent [REDACTED]")
    end
  end

  it "applies the agent's egress policy" do
    agent = create(:agent)
    allow(NetworkEgress::PolicyCheck).to receive(:call)
      .and_return(NetworkEgress::PolicyCheck::Result.new(allowed?: false, reason: "not in allowlist"))

    result = described_class.call(connector: connector, operation: "get_widget", params: { "id" => "1" }, agent: agent)

    expect(result.error).to include("Egress blocked")
  end
end
