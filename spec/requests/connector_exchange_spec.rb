# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connector export and import", type: :request do
  let(:secret) { "tok-supersecret-98765" }
  let(:connector) do
    create(:connector, name: "Widgets", slug: "widgets", base_url: "https://api.widgets.test/v1", auth_scheme: "api_key_header",
                       auth_config: { "header_name" => "X-Api-Key", "secret" => "vault:widgets/token" },
                       operations: [ { "name" => "ping", "description" => "Ping", "method" => "GET", "path" => "/ping", "read_only" => true } ])
  end

  before do
    sign_in create(:user, :owner)
    VaultEntry.create!(namespace: "widgets", key: "token", encrypted_value: secret)
  end

  it "exports the definition without any vault value or key name" do
    get export_connector_path(connector)

    expect(response.headers["Content-Disposition"]).to include("widgets.connector.json")
    expect(response.body).not_to include(secret)
    expect(response.body).not_to include("vault:widgets/token")
    doc = JSON.parse(response.body)
    expect(doc["auth_config"]).to eq("header_name" => "X-Api-Key", "secret" => "vault:replace_me/secret")
    expect(doc).to include("name" => "Widgets", "base_url" => "https://api.widgets.test/v1")
    expect(doc["operations"].size).to eq(1)
  end

  it "imports an export as a new disabled connector with a free slug" do
    get export_connector_path(connector)

    expect { post import_connectors_path, params: { connector_json: response.body } }.to change(Connector, :count).by(1)

    imported = Connector.order(:id).last
    expect(imported).to have_attributes(enabled: false, slug: "widgets_2", name: "Widgets")
    expect(imported.auth_config["secret"]).to eq("vault:replace_me/secret")
    expect(response).to redirect_to(edit_connector_path(imported))
  end

  it "ignores an enabled flag in the pasted JSON" do
    doc = Connectors::Exchange.export(connector).merge("enabled" => true, "slug" => "fresh")

    post import_connectors_path, params: { connector_json: doc.to_json }

    expect(Connector.find_by(slug: "fresh").enabled).to be(false)
  end

  it "rejects JSON that is not a connector export" do
    expect { post import_connectors_path, params: { connector_json: "{\"name\":\"x\"}" } }.not_to change(Connector, :count)

    expect(flash[:alert]).to include("not a Hivemind connector export")
  end

  it "rejects an invalid definition with the reason" do
    doc = Connectors::Exchange.export(connector).merge("base_url" => "http://example.com")

    expect { post import_connectors_path, params: { connector_json: doc.to_json } }.not_to change(Connector, :count)
    expect(flash[:alert]).to include("https")
  end
end
