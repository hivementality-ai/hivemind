# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ConnectorCreator, type: :service do
  let(:agent) { create(:agent) }
  let(:operations) { attributes_for(:connector)[:operations] }
  let(:params) do
    {
      agent: agent,
      name: "Widgets",
      slug: "widgets",
      base_url: "https://api.widgets.test/v1",
      auth_scheme: "bearer",
      auth_config: { "secret" => "vault:widgets/token" },
      operations: operations
    }
  end

  describe ".call" do
    it "saves a disabled connector that waits for approval" do
      result = described_class.call(**params)

      expect(result).to be_success
      expect(result.data[:status]).to eq("pending_approval")
      connector = Connector.find(result.data[:connector_id])
      expect(connector).not_to be_enabled
      expect(connector).to be_pending_approval
      expect(connector.created_by).to eq(agent)
    end

    it "tells the agent which vault entry the user must fill" do
      result = described_class.call(**params)

      expect(result.data[:output]).to include("vault:widgets/token")
    end

    it "opens an approval request that names the connector and holds no secret" do
      result = described_class.call(**params)

      approval = ApprovalRequest.find_by(action: "create_connector")
      expect(approval.params["connector_id"]).to eq(result.data[:connector_id])
      expect(approval.params["secret_refs"]).to eq([ "vault:widgets/token" ])
    end

    it "keeps a pending connector out of the agent tool list" do
      described_class.call(**params)

      expect(Connectors::ToolResolver.proxies(agent)).to be_empty
    end

    it "refuses a raw secret and saves nothing" do
      result = described_class.call(**params.merge(auth_config: { "secret" => "sk-live-abc123" }))

      expect(result).not_to be_success
      expect(result.error).to include("vault reference")
      expect(result.error).not_to include("sk-live-abc123")
      expect(Connector.count).to eq(0)
      expect(ApprovalRequest.where(action: "create_connector")).to be_empty
    end

    it "refuses a key placed in the base URL" do
      result = described_class.call(**params.merge(base_url: "https://user:sk-live-abc123@api.widgets.test/v1"))

      expect(result).not_to be_success
      expect(Connector.count).to eq(0)
    end
  end
end
