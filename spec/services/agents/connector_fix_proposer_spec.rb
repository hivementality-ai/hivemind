# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::ConnectorFixProposer, type: :service do
  let(:agent) { create(:agent) }
  let(:connector) { create(:connector, :bearer, health: { "get_widget" => { "consecutive_failures" => 3 } }) }
  let(:fixed_operations) do
    ops = connector.operations.deep_dup
    ops.first["path"] = "/items/{id}"
    ops
  end

  def propose(**overrides)
    described_class.call(agent: agent, slug: connector.slug, operations: fixed_operations, **overrides)
  end

  def approval_for(result)
    ApprovalRequest.find(result.data[:approval_id])
  end

  it "opens an approval with a before/after diff of only the changed operations" do
    result = propose

    expect(result).to be_success
    approval = approval_for(result)
    expect(approval.action).to eq("update_connector")
    expect(approval.params["changes"].map { |c| c["name"] }).to eq([ "get_widget" ])
    change = approval.params["changes"].first
    expect(change["before"]["path"]).to eq("/widgets/{id}")
    expect(change["after"]["path"]).to eq("/items/{id}")
  end

  it "changes nothing until approved" do
    propose

    expect(connector.reload.operations.first["path"]).to eq("/widgets/{id}")
  end

  it "refuses auth changes and secrets" do
    result = propose(extra: { "auth_config" => { "secret" => "vault:other/key" } })

    expect(result).not_to be_success
    expect(result.error).to include("authentication or secrets")
    expect(ApprovalRequest.count).to eq(0)
  end

  it "refuses an invalid definition" do
    bad = fixed_operations.tap { |ops| ops.first["path"] = "/items/{missing}" }

    expect(propose(operations: bad)).not_to be_success
    expect(ApprovalRequest.count).to eq(0)
  end

  it "refuses a fix identical to the current definition" do
    expect(propose(operations: connector.operations)).not_to be_success
  end

  it "refuses an unknown connector" do
    result = described_class.call(agent: agent, slug: "nope", operations: fixed_operations)

    expect(result.error).to include("not found")
  end

  it "includes a new base_url in the diff" do
    result = propose(base_url: "https://api.widgets.test/v2")

    expect(approval_for(result).params["changes"].map { |c| c["name"] }).to include("base_url")
  end

  describe "resolving the approval" do
    let(:approval) { approval_for(propose(base_url: "https://api.widgets.test/v2")) }

    it "applies the fix and resets health when approved" do
      result = Approvals::Resolve.call(approval_id: approval.id, decision: "approved", resolved_by: 1)

      expect(result).to be_success
      connector.reload
      expect(connector.operations.first["path"]).to eq("/items/{id}")
      expect(connector.base_url).to eq("https://api.widgets.test/v2")
      expect(connector.health).to eq({})
    end

    it "leaves the connector untouched when rejected" do
      Approvals::Resolve.call(approval_id: approval.id, decision: "rejected", resolved_by: 1)

      connector.reload
      expect(connector.operations.first["path"]).to eq("/widgets/{id}")
      expect(connector.base_url).to eq("https://api.widgets.test/v1")
      expect(connector.health["get_widget"]["consecutive_failures"]).to eq(3)
    end
  end
end
