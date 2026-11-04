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
end
