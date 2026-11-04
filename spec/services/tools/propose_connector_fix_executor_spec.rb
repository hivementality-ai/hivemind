# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tools::ProposeConnectorFixExecutor, type: :service do
  let(:agent) { create(:agent) }
  let(:connector) { create(:connector, :bearer) }
  let(:operations) { connector.operations.deep_dup.tap { |ops| ops.first["path"] = "/items/{id}" } }

  def run(payload)
    described_class.new(input: payload, agent: agent).call
  end

  it "opens an approval for a valid fix" do
    expect(run("slug" => connector.slug, "operations" => operations)).to be_success
    expect(ApprovalRequest.pluck(:action)).to eq([ "update_connector" ])
  end

  it "refuses when the input tries to change auth" do
    result = run("slug" => connector.slug, "operations" => operations, "auth_scheme" => "none")

    expect(result).not_to be_success
    expect(ApprovalRequest.count).to eq(0)
  end

  it "is registered as an executor type" do
    expect(Tools::Executor::BUILTIN_EXECUTORS["propose_connector_fix"]).to eq(described_class)
  end
end
