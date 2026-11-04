# frozen_string_literal: true

require "rails_helper"

RSpec.describe Approvals::Resolve, "for connectors", type: :service do
  let(:agent) { create(:agent) }
  let(:connector) { create(:connector, :bearer, enabled: false, pending_approval: true) }
  let(:approval) do
    create(:approval_request, agent: agent, action: "create_connector", resource: "Connector##{connector.id}",
                              params: { "connector_id" => connector.id })
  end

  it "enables the connector when approved" do
    result = described_class.call(approval_id: approval.id, decision: "approved", resolved_by: 1)

    expect(result).to be_success
    expect(connector.reload).to be_enabled
    expect(connector).not_to be_pending_approval
  end

  it "offers the approved connector's operations as tools" do
    described_class.call(approval_id: approval.id, decision: "approved", resolved_by: 1)

    names = Connectors::ToolResolver.proxies(agent).map(&:name)
    expect(names).to include("connector__#{connector.slug}__get_widget")
  end

  it "leaves the connector disabled when rejected" do
    described_class.call(approval_id: approval.id, decision: "rejected", resolved_by: 1)

    expect(connector.reload).not_to be_enabled
  end
end
