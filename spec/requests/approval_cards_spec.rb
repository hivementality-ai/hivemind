# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Approval cards", type: :request do
  let(:owner) { create(:user, :owner) }
  let(:agent) { create(:agent, name: "Sam") }
  let(:session) { create(:session, agent: agent, metadata: { "started_by" => 1 }) }
  let(:tool) { create(:tool, name: "send_mail", executor_type: "email") }
  let(:email) { { "action" => "send", "to" => "pat@example.com", "subject" => "Hello", "body" => "Hi Pat" } }
  let(:runs) { [] }
  let(:stream) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:approval) { ApprovalRequest.find_by!(action: "tool_call") }

  before do
    allow(Tools::EmailExecutor).to receive(:new) do |input:, **|
      runs << input
      instance_double(Tools::EmailExecutor, call: ServiceResponse.success(data: { output: "sent", exit_code: 0 }))
    end
    Tools::Executor.call(tool: tool, input: email, agent: agent, session: session)
    sign_in owner
  end

  it "approves and runs the stored email once, even on a double click" do
    post approve_approval_card_path(approval), headers: stream
    post approve_approval_card_path(approval), headers: stream

    expect(runs).to eq([ email ])
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
  end

  it "replaces the card with its finished state" do
    post approve_approval_card_path(approval), headers: stream

    expect(response.body).to include("turbo-stream")
    expect(approval.reload).to be_approved
  end

  it "runs edited arguments from the edit form" do
    post approve_with_edits_approval_card_path(approval), params: { edits: { subject: "Changed" } }, headers: stream

    expect(runs).to eq([ email.merge("subject" => "Changed") ])
  end

  it "declines without running" do
    post decline_approval_card_path(approval), headers: stream

    expect(runs).to be_empty
    expect(approval.reload).to be_rejected
  end

  it "falls back to a redirect without Turbo" do
    post approve_approval_card_path(approval)

    expect(response).to have_http_status(:redirect)
  end

  it "404s for approvals that are not tool calls" do
    other = create(:approval_request, :pending, agent: agent, action: "execute_command")

    post approve_approval_card_path(other)

    expect(response).to have_http_status(:not_found)
  end

  it "keeps members who are not admins or owners out" do
    sign_in create(:user)

    post approve_approval_card_path(approval)

    expect(runs).to be_empty
    expect(approval.reload).to be_pending
  end

  describe "the chat page" do
    it "shows the pending card with its exact content and three buttons" do
      get session_path(session)

      expect(response.body).to include("Sam wants to send an email").and include("pat@example.com").and include("Hi Pat")
      expect(response.body).to include("Approve").and include("Edit").and include("Decline")
    end
  end

  describe "the approvals inbox" do
    it "lists a held unattended call with its card, and the card's buttons work" do
      heartbeat = create(:session, agent: agent, metadata: { "type" => "heartbeat" })
      Tools::Executor.call(tool: tool, input: email.merge("subject" => "Held"), agent: agent, session: heartbeat)
      held = ApprovalRequest.pending.where(action: "tool_call").order(:id).last

      allow(Redis).to receive(:current).and_return(instance_double(Redis, keys: [], get: nil, ttl: 900, scan_each: [].each))
      get approvals_path

      expect(response.body).to include("Sam wants to send an email").and include("Held").and include(approve_approval_card_path(held))

      post approve_approval_card_path(held), headers: stream
      expect(runs).to eq([ email.merge("subject" => "Held") ])
    end
  end

  describe "switches" do
    it "saves the plain-words toggle on the agent" do
      patch agent_path(agent), params: { agent: { ask_first: { send_email: "0" } } }

      expect(agent.reload.asks_first?("send_email")).to be(false)
    end

    it "lets a scheduled task be set to send without asking" do
      task = create(:scheduled_task, agent: agent)

      patch scheduled_task_path(task), params: { scheduled_task: { allow_sending: "1" } }

      expect(task.reload.allow_sending).to be(true)
    end
  end
end
