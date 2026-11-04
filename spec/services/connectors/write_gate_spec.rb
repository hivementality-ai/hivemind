# frozen_string_literal: true

require "rails_helper"

RSpec.describe Connectors::WriteGate do
  include ActiveJob::TestHelper

  let(:agent) { create(:agent) }
  let(:session) { create(:session, agent: agent, session_key: "wg-#{SecureRandom.hex(4)}") }
  let!(:connector) { create(:connector, :bearer) }
  let(:write_stub) { stub_request(:post, "https://api.widgets.test/v1/widgets") }

  before do
    allow(Connectors::AddressGuard).to receive(:lookup).and_return([ "93.184.216.34" ])
    create(:vault_entry, namespace: "widgets", key: "token", value: "sk-super-secret-value")
  end

  def proxy(operation)
    Connectors::ToolResolver.proxies(agent).find { |tool| tool.name == "connector__#{connector.slug}__#{operation}" }
  end

  def run_tool(tool, input)
    Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
  end

  def proxies_for(ops)
    conn = build(:connector, operations: ops)
    ops.map { |op| Connectors::ToolProxy.new(name: op["name"], connector: conn, operation: op) }
  end

  shared_examples "a held write" do
    it "does not run the call and tells the model it is waiting" do
      write_stub
      result = call_write

      expect(result).to be_success
      expect(result.data[:output]).to include("waiting for a person to approve")
      expect(a_request(:any, /api\.widgets\.test/)).not_to have_been_made
    end

    it "stores the call as a pending approval" do
      expect { call_write }.to change { ApprovalRequest.pending.where(action: "connector_call").count }.by(1)

      approval = ApprovalRequest.find_by!(action: "connector_call")
      expect(approval.agent).to eq(agent)
      expect(approval.params).to include(
        "connector_id" => connector.id, "operation" => "create_widget", "method" => "POST",
        "path" => "/widgets", "arguments" => { "title" => "Sprocket" }
      )
    end
  end

  describe "direct connector tool" do
    let(:call_write) { run_tool(proxy("create_widget"), { "title" => "Sprocket" }) }

    it_behaves_like "a held write"
  end

  describe "through use_tool" do
    let(:call_write) do
      run_tool(SystemTool::USE_TOOL,
               { "name" => "connector__#{connector.slug}__create_widget", "arguments" => { "title" => "Sprocket" } })
    end

    it_behaves_like "a held write"
  end

  describe "read-only operations" do
    it "run straight away" do
      stub = stub_request(:get, "https://api.widgets.test/v1/widgets/7").to_return(status: 200, body: "{}")

      result = run_tool(proxy("get_widget"), { "id" => "7" })

      expect(result).to be_success
      expect(stub).to have_been_requested
      expect(ApprovalRequest.count).to eq(0)
    end

    it "treat GET and HEAD as read-only when no flag is set" do
      ops = [ { "name" => "peek", "description" => "d", "method" => "HEAD", "path" => "/p" },
              { "name" => "drop", "description" => "d", "method" => "DELETE", "path" => "/p" } ]

      expect(proxies_for(ops).map(&:read_only?)).to eq([ true, false ])
    end

    it "let an explicit read_only flag override the method" do
      ops = [ { "name" => "search", "description" => "d", "method" => "POST", "path" => "/s", "read_only" => true },
              { "name" => "odd", "description" => "d", "method" => "GET", "path" => "/o", "read_only" => false } ]

      expect(proxies_for(ops).map(&:read_only?)).to eq([ true, false ])
    end
  end

  describe "resolving the approval" do
    let!(:approval) do
      run_tool(proxy("create_widget"), { "title" => "Sprocket" })
      ApprovalRequest.find_by!(action: "connector_call")
    end

    it "runs the call exactly once with the stored arguments when approved" do
      stub = write_stub.with(body: { title: "Sprocket" }.to_json).to_return(status: 201, body: '{"id":"1"}')

      Approvals::Resolve.call(approval_id: approval.id, decision: "approved", resolved_by: 1)
      Approvals::Resolve.call(approval_id: approval.id, decision: "approved", resolved_by: 1)

      expect(stub).to have_been_requested.once
      log = AuditLog.find_by!(action: "connector_call_executed")
      expect(log.metadata).to include("success" => true, "output" => '{"id":"1"}')
    end

    it "never runs the call when rejected" do
      write_stub
      Approvals::Resolve.call(approval_id: approval.id, decision: "rejected", resolved_by: 1)

      expect(a_request(:any, /api\.widgets\.test/)).not_to have_been_made
      expect(AuditLog.where(action: "connector_call_executed")).to be_empty
    end

    it "does not run the call when the connector has been turned off" do
      connector.update!(enabled: false)
      write_stub

      response = Approvals::Resolve.call(approval_id: approval.id, decision: "approved", resolved_by: 1)

      expect(a_request(:any, /api\.widgets\.test/)).not_to have_been_made
      expect(response.data[:outcome]).to include("Did not run", "disabled")
      expect(response.data[:outcome_ok]).to be(false)
    end

    it "queues the outcome note for the originating chat session" do
      write_stub.to_return(status: 500, body: "boom")

      expect { Approvals::Resolve.call(approval_id: approval.id, decision: "approved", resolved_by: 1) }
        .to have_enqueued_job(ApprovalSessionNoteJob)
        .with(session.id, "Approval result: Ran POST /widgets on #{connector.name}: failed: HTTP 500: boom")
    end

    it "stores the originating session id on the approval" do
      expect(approval.params["session_id"]).to eq(session.id)
    end

    it "keeps secret values out of the stored request" do
      expect(approval.params.to_json).not_to include("sk-super-secret-value")
    end
  end
end
