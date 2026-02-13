# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Approvals::Resolve do
  describe '.call' do
    let(:agent) { create(:agent) }
    let(:approval_request) do
      create(:approval_request,
             agent: agent,
             action: "delete_file",
             resource: "documents/test.txt",
             params: { force: true },
             status: "pending")
    end
    let(:resolved_by) { "admin_user_123" }
    let(:notes) { "Approved for cleanup purposes" }

    before do
      # Mock external dependencies
      allow(ActionCable.server).to receive(:broadcast)
      allow(AuditLog).to receive(:create)
      allow(Rails.logger).to receive(:info)
    end

    describe 'successful approval resolution' do
      it 'approves the request and updates status' do
        freeze_time do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "approved",
            resolved_by: resolved_by,
            notes: notes
          )

          expect(result).to be_a(ServiceResponse)
          expect(result.success?).to be true

          approval_request.reload
          expect(approval_request.status).to eq("approved")
          expect(approval_request.resolved_at).to eq(Time.current)
          expect(approval_request.resolved_by).to eq(resolved_by)
          expect(approval_request.resolution_notes).to eq(notes)
        end
      end

      it 'rejects the request and updates status' do
        freeze_time do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "rejected",
            resolved_by: resolved_by,
            notes: "Security concerns"
          )

          expect(result.success?).to be true

          approval_request.reload
          expect(approval_request.status).to eq("rejected")
          expect(approval_request.resolved_at).to eq(Time.current)
          expect(approval_request.resolved_by).to eq(resolved_by)
          expect(approval_request.resolution_notes).to eq("Security concerns")
        end
      end

      it 'broadcasts resolution to UI' do
        freeze_time do
          described_class.call(
            approval_id: approval_request.id,
            decision: "approved",
            resolved_by: resolved_by,
            notes: notes
          )

          expect(ActionCable.server).to have_received(:broadcast).with(
            "approvals",
            {
              type: "approval_resolved",
              approval: {
                id: approval_request.id,
                status: "approved",
                resolved_at: Time.current.iso8601,
                resolved_by: resolved_by,
                notes: notes
              }
            }
          )
        end
      end

      it 'creates audit log entry' do
        described_class.call(
          approval_id: approval_request.id,
          decision: "approved",
          resolved_by: resolved_by,
          notes: notes
        )

        expect(AuditLog).to have_received(:create).with(
          actor_type: "User",
          actor_id: resolved_by,
          action: "approval_approved",
          resource_type: "ApprovalRequest",
          resource_id: approval_request.id,
          metadata: {
            original_action: "delete_file",
            resource: "documents/test.txt",
            params: { "force" => true },
            notes: notes
          }
        )
      end

      it 'executes pending action when approved' do
        described_class.call(
          approval_id: approval_request.id,
          decision: "approved",
          resolved_by: resolved_by
        )

        expect(Rails.logger).to have_received(:info).with(
          "Executing approved action: delete_file on documents/test.txt"
        )
      end

      it 'does not execute pending action when rejected' do
        described_class.call(
          approval_id: approval_request.id,
          decision: "rejected",
          resolved_by: resolved_by
        )

        expect(Rails.logger).not_to have_received(:info)
      end

      it 'returns approval data' do
        result = described_class.call(
          approval_id: approval_request.id,
          decision: "approved",
          resolved_by: resolved_by,
          notes: notes
        )

        approval = result.data[:approval]
        expect(approval).to eq(approval_request)
        expect(approval.status).to eq("approved")
        expect(approval.resolved_by).to eq(resolved_by)
        expect(approval.resolution_notes).to eq(notes)
      end
    end

    describe 'resolution without notes' do
      it 'works without resolution notes' do
        result = described_class.call(
          approval_id: approval_request.id,
          decision: "approved",
          resolved_by: resolved_by
        )

        expect(result.success?).to be true

        approval_request.reload
        expect(approval_request.resolution_notes).to be_nil
      end

      it 'broadcasts without notes' do
        described_class.call(
          approval_id: approval_request.id,
          decision: "approved",
          resolved_by: resolved_by
        )

        expect(ActionCable.server).to have_received(:broadcast) do |channel, data|
          expect(data[:approval][:notes]).to be_nil
        end
      end
    end

    describe 'validation failures' do
      context 'when approval request does not exist' do
        it 'returns failure for non-existent approval' do
          result = described_class.call(
            approval_id: 99999,
            decision: "approved",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Approval request not found")
        end

        it 'does not broadcast or create audit log for non-existent approval' do
          described_class.call(
            approval_id: 99999,
            decision: "approved",
            resolved_by: resolved_by
          )

          expect(ActionCable.server).not_to have_received(:broadcast)
          expect(AuditLog).not_to have_received(:create)
        end
      end

      context 'when approval request already resolved' do
        before do
          approval_request.update!(status: "approved", resolved_at: 1.hour.ago)
        end

        it 'returns failure for already resolved approval' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "rejected",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Approval request already resolved")
        end
      end

      context 'when approval request has expired' do
        before do
          approval_request.update!(expires_at: 1.hour.ago)
        end

        it 'returns failure for expired approval' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "approved",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Approval request expired")
        end
      end

      context 'with invalid decision' do
        it 'returns failure for invalid decision' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "maybe",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Invalid decision")
        end

        it 'returns failure for empty decision' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Invalid decision")
        end

        it 'returns failure for nil decision' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: nil,
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Invalid decision")
        end
      end
    end

    describe 'decision case sensitivity' do
      it 'accepts lowercase "approved"' do
        result = described_class.call(
          approval_id: approval_request.id,
          decision: "approved",
          resolved_by: resolved_by
        )

        expect(result.success?).to be true
      end

      it 'accepts lowercase "rejected"' do
        result = described_class.call(
          approval_id: approval_request.id,
          decision: "rejected",
          resolved_by: resolved_by
        )

        expect(result.success?).to be true
      end

      it 'rejects uppercase decisions' do
        result = described_class.call(
          approval_id: approval_request.id,
          decision: "APPROVED",
          resolved_by: resolved_by
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Invalid decision")
      end

      it 'rejects mixed case decisions' do
        result = described_class.call(
          approval_id: approval_request.id,
          decision: "Approved",
          resolved_by: resolved_by
        )

        expect(result.success?).to be false
        expect(result.error).to eq("Invalid decision")
      end
    end

    describe 'exception handling' do
      context 'when approval update raises exception' do
        before do
          allow(approval_request).to receive(:update!).and_raise(ActiveRecord::RecordInvalid, "Validation failed")
          allow(ApprovalRequest).to receive(:find_by).and_return(approval_request)
        end

        it 'returns failure with error message' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "approved",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Resolution failed: Validation failed")
        end
      end

      context 'when ActionCable broadcast raises exception' do
        before do
          allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "ActionCable error")
        end

        it 'returns failure with error message' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "approved",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Resolution failed: ActionCable error")
        end
      end

      context 'when audit log creation raises exception' do
        before do
          allow(AuditLog).to receive(:create).and_raise(StandardError, "Audit system down")
        end

        it 'returns failure with error message' do
          result = described_class.call(
            approval_id: approval_request.id,
            decision: "approved",
            resolved_by: resolved_by
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Resolution failed: Audit system down")
        end
      end
    end

    describe 'different approval types' do
      it 'handles file deletion approvals' do
        file_approval = create(:approval_request,
                               action: "delete_file",
                               resource: "/sensitive/data.txt",
                               params: { recursive: false })

        result = described_class.call(
          approval_id: file_approval.id,
          decision: "approved",
          resolved_by: resolved_by
        )

        expect(result.success?).to be true
        expect(Rails.logger).to have_received(:info).with(
          "Executing approved action: delete_file on /sensitive/data.txt"
        )
      end

      it 'handles API call approvals' do
        api_approval = create(:approval_request,
                              action: "external_api_call",
                              resource: "https://api.example.com/users",
                              params: { method: "POST", data: { user: "test" } })

        result = described_class.call(
          approval_id: api_approval.id,
          decision: "approved",
          resolved_by: resolved_by
        )

        expect(result.success?).to be true
        expect(Rails.logger).to have_received(:info).with(
          "Executing approved action: external_api_call on https://api.example.com/users"
        )
      end

      it 'handles message sending approvals' do
        message_approval = create(:approval_request,
                                  action: "send_message",
                                  resource: "admin@example.com",
                                  params: { subject: "Alert", body: "System issue detected" })

        result = described_class.call(
          approval_id: message_approval.id,
          decision: "rejected",
          resolved_by: resolved_by,
          notes: "Too sensitive for automated sending"
        )

        expect(result.success?).to be true
        # Should not log execution for rejected approvals
        expect(Rails.logger).not_to have_received(:info)
      end
    end

    describe 'audit log variations' do
      it 'creates correct audit log for rejection' do
        described_class.call(
          approval_id: approval_request.id,
          decision: "rejected",
          resolved_by: resolved_by,
          notes: "Security policy violation"
        )

        expect(AuditLog).to have_received(:create).with(
          actor_type: "User",
          actor_id: resolved_by,
          action: "approval_rejected",
          resource_type: "ApprovalRequest",
          resource_id: approval_request.id,
          metadata: {
            original_action: approval_request.action,
            resource: approval_request.resource,
            params: approval_request.params,
            notes: "Security policy violation"
          }
        )
      end

      it 'includes nil notes in audit log when no notes provided' do
        described_class.call(
          approval_id: approval_request.id,
          decision: "approved",
          resolved_by: resolved_by
        )

        expect(AuditLog).to have_received(:create) do |args|
          expect(args[:metadata][:notes]).to be_nil
        end
      end
    end
  end
end