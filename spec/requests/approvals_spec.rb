# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Approvals", type: :request do
  let(:owner) { create(:user, :owner) }

  before do
    # Stub Redis so vault_confirmation tests don't need a live Redis.
    allow(Redis).to receive(:current).and_return(redis_double)
  end

  let(:redis_double) do
    instance_double(Redis,
      keys: [],
      get: nil,
      ttl: 900,
      del: 1,
      setex: "OK",
      # The layout's provider-circuit banner scans for open circuits on
      # every render; no circuits here.
      scan_each: [].each)
  end

  describe "GET /approvals (index)" do
    context "as owner" do
      before { sign_in owner }

      it "renders all three sections" do
        get approvals_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Approval Requests")
        expect(response.body).to include("Vault Write Confirmations")
        expect(response.body).to include("Skill Update Proposals")
      end

      it "shows pending approval requests" do
        agent = create(:agent)
        create(:approval_request, :pending, agent: agent, action: "execute_command")
        allow(redis_double).to receive(:keys).and_return([])

        get approvals_path
        expect(response.body).to include("execute_command")
      end

      it "shows pending skill update proposals" do
        proposal = create(:skill_update_proposal, status: "pending")
        get approvals_path
        expect(response.body).to include(proposal.skill.name)
      end

      it "shows pending vault confirmations from Redis" do
        confirmation_id = "abc123"
        payload = JSON.generate(
          "agent_id" => 99, "agent_name" => "Vault Agent",
          "namespace" => "openai", "key" => "api_key",
          "value" => "sk-secret", "purpose" => "LLM calls", "tool_binding" => nil
        )
        allow(redis_double).to receive(:keys).and_return([ "vault_write_confirmation:#{confirmation_id}" ])
        allow(redis_double).to receive(:get).with("vault_write_confirmation:#{confirmation_id}").and_return(payload)
        allow(redis_double).to receive(:ttl).with("vault_write_confirmation:#{confirmation_id}").and_return(600)

        get approvals_path
        expect(response.body).to include("openai.api_key")
        expect(response.body).to include("Vault Agent")
      end
    end

    context "as viewer" do
      before { sign_in create(:user, :viewer) }

      it "is denied" do
        get approvals_path
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "POST /approvals/:id/approve" do
    before { sign_in owner }

    context "approval_request type" do
      it "approves and redirects" do
        agent = create(:agent)
        req = create(:approval_request, :pending, agent: agent)

        allow(Approvals::Resolve).to receive(:call).and_return(ServiceResponse.success)

        post approve_approval_path(req, approval_type: "approval_request")

        expect(Approvals::Resolve).to have_received(:call).with(
          approval_id: req.id.to_s,
          decision: "approved",
          resolved_by: owner.id
        )
        expect(response).to redirect_to(approvals_path)
        follow_redirect!
        expect(response.body).to include("approved")
      end
    end

    context "vault_confirmation type" do
      it "calls confirm_write and redirects" do
        agent = create(:agent)
        confirmation_id = "deadbeef"
        payload = JSON.generate(
          "agent_id" => agent.id, "agent_name" => agent.name,
          "namespace" => "stripe", "key" => "sk", "value" => "sk_live_x",
          "purpose" => nil, "tool_binding" => nil
        )
        allow(redis_double).to receive(:get).with("vault_write_confirmation:#{confirmation_id}").and_return(payload)
        allow(Vault::WriteConfirmation).to receive(:confirm_write).and_return({ status: "written" })

        post approve_approval_path(confirmation_id, approval_type: "vault_confirmation")

        expect(Vault::WriteConfirmation).to have_received(:confirm_write).with(
          confirmation_id: confirmation_id,
          agent: agent
        )
        expect(response).to redirect_to(approvals_path)
      end
    end

    context "skill_update_proposal type" do
      it "calls UpdateApprover and redirects" do
        proposal = create(:skill_update_proposal)

        allow(Skills::UpdateApprover).to receive(:call).and_return(ServiceResponse.success)

        post approve_approval_path(proposal, approval_type: "skill_update_proposal")

        expect(Skills::UpdateApprover).to have_received(:call).with(
          proposal: proposal,
          approved_by: owner.id
        )
        expect(response).to redirect_to(approvals_path)
      end
    end
  end

  describe "POST /approvals/:id/reject" do
    before { sign_in owner }

    context "approval_request type" do
      it "rejects and redirects" do
        agent = create(:agent)
        req = create(:approval_request, :pending, agent: agent)
        allow(Approvals::Resolve).to receive(:call).and_return(ServiceResponse.success)

        post reject_approval_path(req, approval_type: "approval_request")

        expect(Approvals::Resolve).to have_received(:call).with(
          approval_id: req.id.to_s,
          decision: "rejected",
          resolved_by: owner.id
        )
        expect(response).to redirect_to(approvals_path)
      end
    end

    context "vault_confirmation type" do
      it "deletes the Redis key and redirects" do
        confirmation_id = "cafebabe"
        allow(redis_double).to receive(:del).with("vault_write_confirmation:#{confirmation_id}").and_return(1)

        post reject_approval_path(confirmation_id, approval_type: "vault_confirmation")

        expect(redis_double).to have_received(:del).with("vault_write_confirmation:#{confirmation_id}")
        expect(response).to redirect_to(approvals_path)
      end
    end

    context "skill_update_proposal type" do
      it "calls UpdateRejector and redirects" do
        proposal = create(:skill_update_proposal)
        allow(Skills::UpdateRejector).to receive(:call).and_return(ServiceResponse.success)

        post reject_approval_path(proposal, approval_type: "skill_update_proposal")

        expect(Skills::UpdateRejector).to have_received(:call).with(
          proposal: proposal,
          rejected_by: owner.id
        )
        expect(response).to redirect_to(approvals_path)
      end
    end

    context "as viewer" do
      before { sign_in create(:user, :viewer) }

      it "is denied" do
        agent = create(:agent)
        req = create(:approval_request, :pending, agent: agent)
        post reject_approval_path(req, approval_type: "approval_request")
        expect(response).to redirect_to(root_path)
      end
    end
  end
end
