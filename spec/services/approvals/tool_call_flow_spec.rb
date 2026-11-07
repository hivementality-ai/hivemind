# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Approval cards for tool calls" do
  include ActiveJob::TestHelper

  let(:agent) { create(:agent, name: "Sam") }
  let(:session) { create(:session, agent: agent) }
  let(:tool) { create(:tool, name: "send_mail", executor_type: "email") }
  let(:email) { { "action" => "send", "to" => "pat@example.com", "subject" => "Hello", "body" => "Hi Pat" } }
  let(:runs) { [] }

  before do
    allow(Tools::EmailExecutor).to receive(:new) do |input:, **|
      runs << input
      instance_double(Tools::EmailExecutor, call: ServiceResponse.success(data: { output: "sent", exit_code: 0 }))
    end
  end

  def run_tool(input = email, tool: self.tool, session: self.session)
    Tools::Executor.call(tool: tool, input: input, agent: agent, session: session)
  end

  def approval
    ApprovalRequest.find_by!(action: "tool_call")
  end

  def resolve(decision, edits: nil)
    Approvals::Resolve.call(approval_id: approval.id, decision: decision, resolved_by: 1, edits: edits)
  end

  describe "an asks-first tool" do
    it "creates a pending card instead of running" do
      result = run_tool

      expect(result).to be_success
      expect(runs).to be_empty
      expect(ApprovalRequest.pending.where(action: "tool_call").count).to eq(1)
      expect(approval.params).to include("tool_name" => "send_mail", "category" => "send_email",
                                         "session_id" => session.id, "arguments" => email)
    end

    it "tells the model it is waiting and not to retry" do
      expect(run_tool.data[:output]).to include("waiting for the user's OK").and include("do not retry")
    end

    it "describes the action in plain words with the exact content" do
      run_tool
      card = Approvals::CardFields.new(approval)

      expect(card.headline).to eq("Sam wants to send an email")
      expect(card.fields.map { |f| [ f.label, f.value ] }).to eq(
        [ [ "To", "pat@example.com" ], [ "Subject", "Hello" ], [ "Message", "Hi Pat" ] ]
      )
    end

    it "puts the card in the chat stream" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        .with(Approvals::CardStream.stream_name(session), hash_including(target: Approvals::CardStream.container_id(session)))

      run_tool
    end
  end

  describe "reads and switched-off categories" do
    it "run straight away when the call is a read" do
      tool = create(:tool, name: "mail_config", executor_type: "email")

      run_tool({ "action" => "config" }, tool: tool)

      expect(runs).to eq([ { "action" => "config" } ])
      expect(ApprovalRequest.count).to eq(0)
    end

    it "run straight away once the agent stopped asking about that category" do
      agent.update!(ask_first: { "send_email" => "0" })

      run_tool

      expect(runs).to eq([ email ])
      expect(ApprovalRequest.count).to eq(0)
    end
  end

  describe "approving" do
    before { run_tool }

    it "runs the stored arguments exactly" do
      resolve("approved")

      expect(runs).to eq([ email ])
      expect(approval).to be_approved
    end

    it "runs once even when approved twice" do
      resolve("approved")
      second = resolve("approved")

      expect(runs.size).to eq(1)
      expect(second).not_to be_success
      expect(second.error).to include("already resolved")
    end

    it "runs once when a stale copy of the request is approved after another tab already did" do
      stale = ApprovalRequest.find(approval.id)
      resolve("approved")

      result = Approvals::Resolve.call(approval_id: stale.id, decision: "approved", resolved_by: 1)

      expect(result).not_to be_success
      expect(runs.size).to eq(1)
    end

    it "tells the chat what happened" do
      expect { resolve("approved") }
        .to have_enqueued_job(ApprovalSessionNoteJob).with(session.id, a_string_including("Approval result: Ran: send an email"))
    end

    it "does not run an expired request" do
      approval.update!(expires_at: 1.minute.ago)

      result = resolve("approved")

      expect(result.error).to include("expired")
      expect(runs).to be_empty
    end
  end

  describe "editing" do
    before { run_tool }

    it "runs the edited arguments, keeping the rest of the original" do
      resolve("approved", edits: { "subject" => "Hello there", "body" => "Hi Pat, edited" })

      expect(runs).to eq([ email.merge("subject" => "Hello there", "body" => "Hi Pat, edited") ])
      expect(approval.params).to include("edited" => true, "original_arguments" => email)
    end

    it "ignores edits to fields that are not on the card" do
      resolve("approved", edits: { "action" => "config", "subject" => "Changed" })

      expect(runs).to eq([ email.merge("subject" => "Changed") ])
    end
  end

  describe "declining" do
    before { run_tool }

    it "does not run and tells the agent it was declined" do
      expect { resolve("rejected") }
        .to have_enqueued_job(ApprovalSessionNoteJob).with(session.id, a_string_including("declined to send an email").and(including("Carry on without it")))

      expect(runs).to be_empty
      expect(approval).to be_rejected
    end
  end

  describe "expiry" do
    before { run_tool }

    it "marks unanswered requests expired after 24 hours and tells the chat" do
      expect(approval.expires_at).to be_within(1.minute).of(24.hours.from_now)
      approval.update!(expires_at: 1.minute.ago)

      expect { expect(Approvals::ExpireStale.call).to eq(1) }
        .to have_enqueued_job(ApprovalSessionNoteJob).with(session.id, a_string_including("expired after 24 hours"))

      expect(approval).to be_expired
      expect(runs).to be_empty
    end

    it "leaves requests that are still fresh alone" do
      expect(Approvals::ExpireStale.call).to eq(0)
      expect(approval).to be_pending
    end
  end

  describe "unattended runs" do
    let(:task) { create(:scheduled_task, agent: agent) }
    let(:scheduled_session) do
      create(:session, agent: agent, metadata: { "type" => "scheduled", "scheduled_task_id" => task.id })
    end

    it "hold the action and let the run finish when the task may not send" do
      result = run_tool(session: scheduled_session)

      expect(result).to be_success
      expect(runs).to be_empty
      expect(approval.params["unattended"]).to be(true)
      expect(result.data[:output]).to include("Nobody is watching").and include("say clearly in your final answer")
    end

    it "send without a card when the task was set up with sending allowed" do
      task.update!(allow_sending: true)

      run_tool(session: scheduled_session)

      expect(runs).to eq([ email ])
      expect(ApprovalRequest.count).to eq(0)
    end

    it "still hold when only a different task allows sending" do
      create(:scheduled_task, agent: agent, allow_sending: true)

      run_tool(session: scheduled_session)

      expect(runs).to be_empty
      expect(ApprovalRequest.count).to eq(1)
    end

    it "do not let a person-attended chat skip the card because a task allows sending" do
      task.update!(allow_sending: true)

      run_tool

      expect(runs).to be_empty
    end
  end
end
