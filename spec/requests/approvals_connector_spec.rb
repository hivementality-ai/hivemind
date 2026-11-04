# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Approvals page for connectors", type: :request do
  let(:owner) { create(:user, :owner) }
  let(:agent) { create(:agent) }
  let(:redis_double) { instance_double(Redis, keys: [], get: nil, ttl: 900, del: 1, setex: "OK", scan_each: [].each) }

  before do
    allow(Redis).to receive(:current).and_return(redis_double)
    sign_in owner
  end

  it "shows a before/after diff for a proposed fix" do
    connector = create(:connector)
    ops = connector.operations.deep_dup.tap { |o| o.first["path"] = "/items/{id}" }
    Agents::ConnectorFixProposer.call(agent: agent, slug: connector.slug, operations: ops,
                                      base_url: "https://api.widgets.test/v2")

    get approvals_path

    body = response.body
    expect(body).to include("get_widget")
    expect(body).to include("- GET /widgets/{id}")
    expect(body).to include("+ GET /items/{id}")
    expect(body).to include("params: id, verbose")
    expect(body).to include("https://api.widgets.test/v1")
    expect(body).to include("https://api.widgets.test/v2")
  end

  it "shows the details of a connector draft without any secret value" do
    create(:vault_entry, namespace: "widgets", key: "token", value: "sk-super-secret-value")
    Agents::ConnectorCreator.call(
      agent: agent, name: "Widgets", slug: "widgets", base_url: "https://api.widgets.test/v1",
      auth_scheme: "bearer", auth_config: { "secret" => "vault:widgets/token" },
      operations: build(:connector).operations
    )

    get approvals_path

    expect(response.body).to include("Widgets", "https://api.widgets.test/v1", "bearer", "vault:widgets/token", "create_widget")
    expect(response.body).not_to include("sk-super-secret-value")
  end

  it "escapes operation text" do
    create(:approval_request, :pending, agent: agent, action: "update_connector", resource: "Connector#1",
                                         params: { "changes" => [ { "name" => "<script>alert(1)</script>", "change" => "added",
                                                                    "before" => nil,
                                                                    "after" => { "method" => "GET", "path" => "/<b>x</b>" } } ] })

    get approvals_path

    expect(response.body).not_to include("<script>alert(1)</script>")
    expect(response.body).not_to include("/<b>x</b>")
    expect(response.body).to include("&lt;script&gt;")
  end

  it "shows a held write with its connector, request and arguments but no secret" do
    create(:vault_entry, namespace: "widgets", key: "token", value: "sk-super-secret-value")
    connector = create(:connector, :bearer, name: "Widget Shop")
    proxy = Connectors::ToolResolver.proxies(agent).find { |tool| tool.name.end_with?("__create_widget") }
    Tools::Executor.call(tool: proxy, input: { "title" => "Sprocket", "key" => "vault:widgets/token" },
                         agent: agent, session: create(:session, agent: agent, session_key: "ap-#{SecureRandom.hex(4)}"))

    get approvals_path

    expect(connector).to be_persisted
    expect(response.body).to include("Widget Shop", "create_widget", "POST /widgets", "Sprocket", "vault:widgets/token")
    expect(response.body).not_to include("sk-super-secret-value")
  end

  describe "approving a held write" do
    let!(:connector) { create(:connector, name: "Widget Shop") }
    let(:approval) do
      create(:approval_request, :pending, agent: agent, action: "connector_call", resource: "Connector##{connector.id}/create_widget",
                                           params: { "connector_id" => connector.id, "connector_name" => "Widget Shop",
                                                     "operation" => "create_widget", "method" => "POST", "path" => "/widgets",
                                                     "arguments" => { "title" => "Sprocket" } })
    end

    before { allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ]) }

    it "tells the approver the call succeeded" do
      stub_request(:post, "https://api.widgets.test/v1/widgets").to_return(status: 201, body: '{"id":"9"}')

      post approve_approval_path(approval, approval_type: "approval_request")

      expect(flash[:notice]).to include("Ran POST /widgets on Widget Shop: succeeded")
    end

    it "tells the approver the call failed and why" do
      stub_request(:post, "https://api.widgets.test/v1/widgets").to_return(status: 422, body: "title is taken")

      post approve_approval_path(approval, approval_type: "approval_request")

      expect(flash[:alert]).to include("Ran POST /widgets on Widget Shop: failed: HTTP 422: title is taken")
    end

    it "truncates long output" do
      stub_request(:post, "https://api.widgets.test/v1/widgets").to_return(status: 200, body: "x" * 1000)

      post approve_approval_path(approval, approval_type: "approval_request")

      expect(flash[:notice].length).to be < 450
    end

    it "refuses and says so when the connector was turned off" do
      connector.update!(enabled: false)

      post approve_approval_path(approval, approval_type: "approval_request")

      expect(flash[:alert]).to include("Did not run POST /widgets on Widget Shop", "disabled")
      expect(a_request(:any, /api\.widgets\.test/)).not_to have_been_made
    end
  end
end
