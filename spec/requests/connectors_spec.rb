# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connectors", type: :request do
  let(:secret) { "tok-supersecret-98765" }
  let(:valid_operations) do
    [ { "name" => "ping", "description" => "Ping", "method" => "GET", "path" => "/ping", "read_only" => true } ]
  end

  describe "as an owner" do
    before { sign_in create(:user, :owner) }

    it "lists connectors with name, slug, base URL, status and operation count" do
      create(:connector, name: "Widgets", slug: "widgets", base_url: "https://api.widgets.test/v1")
      create(:connector, name: "Gadgets", slug: "gadgets", enabled: false)

      get connectors_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Widgets", "widgets", "https://api.widgets.test/v1", "enabled", "disabled", "Gadgets")
      expect(response.body).to include("Connectors let Hivemind use any app with a web API.")
    end

    it "offers existing vault entries as references on the form" do
      VaultEntry.create!(namespace: "widgets", key: "token", encrypted_value: secret)

      get new_connector_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("vault:widgets/token")
      expect(response.body).not_to include(secret)
    end

    it "creates a connector with vault references and records who made it" do
      post connectors_path, params: { connector: {
        name: "Widgets API", base_url: "https://api.widgets.test/v1", auth_scheme: "bearer", enabled: "1",
        auth: { secret: "vault:widgets/token", header_name: "X-Stale" },
        operations_json: JSON.generate(valid_operations)
      } }

      expect(response).to redirect_to(connectors_path)
      connector = Connector.find_by!(slug: "widgets_api")
      expect(connector).to have_attributes(auth_scheme: "bearer", auth_config: { "secret" => "vault:widgets/token" })
      expect(connector.operations.size).to eq(1)
      expect(connector.created_by).to be_a(User)
    end

    it "re-renders with the model's errors for a raw secret in the auth settings" do
      post connectors_path, params: { connector: {
        name: "Widgets API", base_url: "https://api.widgets.test/v1", auth_scheme: "bearer",
        auth: { secret: secret }, operations_json: "[]"
      } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("must be a vault reference")
      expect(Connector.count).to eq(0)
    end

    it "re-renders with the model's errors for malformed operations" do
      post connectors_path, params: { connector: {
        name: "Widgets API", base_url: "https://api.widgets.test/v1", auth_scheme: "none",
        operations_json: JSON.generate([ { "name" => "Bad Name" } ])
      } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("lowercase snake_case name")
    end

    it "re-renders when the operations are not JSON" do
      post connectors_path, params: { connector: {
        name: "Widgets API", base_url: "https://api.widgets.test/v1", auth_scheme: "none", operations_json: "{nope"
      } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("must be valid JSON")
      expect(Connector.count).to eq(0)
    end

    it "renders the edit form with the operations" do
      connector = create(:connector)

      get edit_connector_path(connector)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("get_widget", "Try it")
    end

    it "updates a connector" do
      connector = create(:connector)

      patch connector_path(connector), params: { connector: {
        name: "Renamed", base_url: connector.base_url, auth_scheme: "none", operations_json: JSON.generate(valid_operations)
      } }

      expect(response).to redirect_to(connectors_path)
      expect(connector.reload).to have_attributes(name: "Renamed")
      expect(connector.operations.map { |op| op["name"] }).to eq([ "ping" ])
    end

    it "keeps the saved connector when an update is invalid" do
      connector = create(:connector, name: "Keep me")

      patch connector_path(connector), params: { connector: { name: "Changed", base_url: "ftp://nope", auth_scheme: "none" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(connector.reload.name).to eq("Keep me")
    end

    it "toggles enabled" do
      connector = create(:connector, enabled: true)

      patch toggle_enabled_connector_path(connector)

      expect(response).to redirect_to(connectors_path)
      expect(connector.reload.enabled).to be(false)
    end

    it "deletes a connector" do
      connector = create(:connector)

      expect { delete connector_path(connector) }.to change(Connector, :count).by(-1)
      expect(response).to redirect_to(connectors_path)
    end

    describe "Try it" do
      let(:connector) { create(:connector) }

      before { allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ]) }

      it "shows the status and the start of the output inline" do
        stub_request(:get, "https://api.widgets.test/v1/widgets/7").to_return(status: 200, body: "x" * 3000)

        post try_operation_connector_path(connector, operation: "get_widget"), params: { input: '{"id": "7"}' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("HTTP 200")
        expect(response.body).to include("x" * 900)
        expect(response.body).not_to include("x" * 1100)
        expect(response.body).to include("Output cut short")
      end

      it "shows the error when the API refuses" do
        stub_request(:get, "https://api.widgets.test/v1/widgets/7").to_return(status: 404, body: "no such widget")

        post try_operation_connector_path(connector, operation: "get_widget"), params: { input: '{"id": "7"}' }

        expect(response.body).to include("HTTP 404", "no such widget")
      end

      it "shows the error for a blocked address and sends nothing" do
        connector.update_column(:base_url, "http://169.254.169.254/latest")

        post try_operation_connector_path(connector, operation: "get_widget"), params: { input: '{"id": "7"}' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("blocked")
        expect(a_request(:any, /169\.254/)).not_to have_been_made
      end

      it "reports inputs that are not JSON" do
        post try_operation_connector_path(connector, operation: "get_widget"), params: { input: "{oops" }

        expect(response.body).to include("Inputs are not valid JSON")
      end

      it "reports an unknown operation" do
        post try_operation_connector_path(connector, operation: "nope"), params: { input: "{}" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Unknown operation nope")
      end

      it "never shows the vault value it sent as auth" do
        VaultEntry.create!(namespace: "widgets", key: "token", encrypted_value: secret)
        bearer = create(:connector, :bearer)
        stub_request(:get, "https://api.widgets.test/v1/widgets/7").to_return(status: 200, body: "echo #{secret}")

        post try_operation_connector_path(bearer, operation: "get_widget"), params: { input: '{"id": "7"}' }

        expect(response.body).to include("HTTP 200", "[REDACTED]")
        expect(response.body).not_to include(secret)
      end
    end
  end

  describe "as a viewer" do
    before { sign_in create(:user, :viewer) }

    it "is denied" do
      get connectors_path
      expect(response).to redirect_to(root_path)
    end

    it "cannot run Try it" do
      connector = create(:connector)
      post try_operation_connector_path(connector, operation: "get_widget"), params: { input: "{}" }
      expect(response).to redirect_to(root_path)
    end
  end

  describe "navigation" do
    before { sign_in create(:user, :owner) }

    it "links both screens from the Integrations page" do
      get integrations_path

      expect(response.body).to include(connectors_path, vault_entries_path)
      expect(response.body).to include("Keys are kept in the vault and never shown to the AI.")
    end
  end
end
