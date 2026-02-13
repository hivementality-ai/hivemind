# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Approvals::Request do
  describe '.call' do
    let(:agent) { create(:agent, name: "Assistant", role: "helper") }
    let(:action) { "delete_file" }
    let(:resource) { "documents/sensitive.txt" }
    let(:params) { { reason: "cleanup", force: true } }

    before do
      # Mock external dependencies
      allow(ActionCable.server).to receive(:broadcast)
      allow(AuditLog).to receive(:create)
    end

    describe 'successful approval request' do
      it 'creates an approval request' do
        expect {
          described_class.call(
            agent: agent,
            action: action,
            resource: resource,
            params: params
          )
        }.to change(ApprovalRequest, :count).by(1)

        approval = ApprovalRequest.last
        expect(approval.agent).to eq(agent)
        expect(approval.action).to eq(action)
        expect(approval.resource).to eq(resource)
        expect(approval.params).to eq(params.stringify_keys)
        expect(approval.expires_at).to be_present
      end

      it 'returns success with approval data' do
        result = described_class.call(
          agent: agent,
          action: action,
          resource: resource,
          params: params
        )

        expect(result).to be_a(ServiceResponse)
        expect(result.success?).to be true
        expect(result.data[:approval]).to be_a(ApprovalRequest)
        expect(result.data[:approval].agent).to eq(agent)
        expect(result.data[:approval].action).to eq(action)
      end

      it 'sets default expiration to 24 hours from now' do
        freeze_time do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource
          )

          approval = result.data[:approval]
          expect(approval.expires_at).to eq(24.hours.from_now)
        end
      end

      it 'accepts custom expiration time' do
        freeze_time do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource,
            expires_in: 2.hours
          )

          approval = result.data[:approval]
          expect(approval.expires_at).to eq(2.hours.from_now)
        end
      end

      it 'broadcasts to UI via ActionCable' do
        freeze_time do
          described_class.call(
            agent: agent,
            action: action,
            resource: resource,
            params: params
          )

          expect(ActionCable.server).to have_received(:broadcast).with(
            "approvals",
            {
              type: "approval_requested",
              approval: {
                id: be_a(Integer),
                agent: {
                  id: agent.id,
                  name: agent.name,
                  role: agent.role
                },
                action: action,
                resource: resource,
                params: params,
                requested_at: be_present,
                expires_at: 24.hours.from_now.iso8601
              }
            }
          )
        end
      end

      it 'creates audit log entry' do
        result = described_class.call(
          agent: agent,
          action: action,
          resource: resource,
          params: params
        )

        approval = result.data[:approval]
        expect(AuditLog).to have_received(:create).with(
          actor_type: "Agent",
          actor_id: agent.id,
          action: "approval_requested",
          resource_type: "ApprovalRequest",
          resource_id: approval.id,
          metadata: {
            action: action,
            resource: resource,
            params: params
          }
        )
      end
    end

    describe 'with minimal parameters' do
      it 'works with empty params' do
        result = described_class.call(
          agent: agent,
          action: action,
          resource: resource
        )

        expect(result.success?).to be true
        approval = result.data[:approval]
        expect(approval.params).to eq({})
      end

      it 'works with nil params' do
        result = described_class.call(
          agent: agent,
          action: action,
          resource: resource,
          params: nil
        )

        expect(result.success?).to be true
        approval = result.data[:approval]
        expect(approval.params).to be_nil
      end
    end

    describe 'validation failures' do
      context 'when approval request creation fails' do
        before do
          allow(ApprovalRequest).to receive(:create).and_return(
            double(
              persisted?: false,
              errors: double(full_messages: ["Agent can't be blank", "Action is invalid"])
            )
          )
        end

        it 'returns failure with validation errors' do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource
          )

          expect(result.success?).to be false
          expect(result.error).to eq(["Agent can't be blank", "Action is invalid"])
        end

        it 'does not broadcast or create audit log on validation failure' do
          described_class.call(
            agent: agent,
            action: action,
            resource: resource
          )

          expect(ActionCable.server).not_to have_received(:broadcast)
          expect(AuditLog).not_to have_received(:create)
        end
      end
    end

    describe 'exception handling' do
      context 'when ApprovalRequest.create raises exception' do
        before do
          allow(ApprovalRequest).to receive(:create).and_raise(StandardError, "Database connection lost")
        end

        it 'returns failure with error message' do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Approval request failed: Database connection lost")
        end
      end

      context 'when ActionCable broadcast raises exception' do
        before do
          allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "ActionCable error")
        end

        it 'returns failure with error message' do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Approval request failed: ActionCable error")
        end
      end

      context 'when audit log creation raises exception' do
        before do
          allow(AuditLog).to receive(:create).and_raise(StandardError, "Audit system down")
        end

        it 'returns failure with error message' do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource
          )

          expect(result.success?).to be false
          expect(result.error).to eq("Approval request failed: Audit system down")
        end
      end
    end

    describe 'complex parameters' do
      let(:complex_params) do
        {
          files: ["file1.txt", "file2.txt"],
          options: { recursive: true, force: true },
          metadata: { requester: "system", priority: "high" }
        }
      end

      it 'handles complex parameter structures' do
        result = described_class.call(
          agent: agent,
          action: "bulk_delete",
          resource: "documents/",
          params: complex_params
        )

        expect(result.success?).to be true
        approval = result.data[:approval]
        expect(approval.params).to eq(complex_params.deep_stringify_keys)
      end

      it 'broadcasts complex parameters correctly' do
        described_class.call(
          agent: agent,
          action: "bulk_delete",
          resource: "documents/",
          params: complex_params
        )

        expect(ActionCable.server).to have_received(:broadcast) do |channel, data|
          expect(data[:approval][:params]).to eq(complex_params)
        end
      end
    end

    describe 'resource types' do
      it 'handles file paths as resources' do
        result = described_class.call(
          agent: agent,
          action: "read",
          resource: "/path/to/sensitive/file.txt"
        )

        expect(result.success?).to be true
        expect(result.data[:approval].resource).to eq("/path/to/sensitive/file.txt")
      end

      it 'handles URLs as resources' do
        result = described_class.call(
          agent: agent,
          action: "api_call",
          resource: "https://api.example.com/users"
        )

        expect(result.success?).to be true
        expect(result.data[:approval].resource).to eq("https://api.example.com/users")
      end

      it 'handles database records as resources' do
        result = described_class.call(
          agent: agent,
          action: "delete",
          resource: "User:123"
        )

        expect(result.success?).to be true
        expect(result.data[:approval].resource).to eq("User:123")
      end
    end

    describe 'expiration handling' do
      it 'accepts expiration in seconds' do
        freeze_time do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource,
            expires_in: 3600 # 1 hour in seconds
          )

          approval = result.data[:approval]
          expect(approval.expires_at).to eq(1.hour.from_now)
        end
      end

      it 'accepts very short expiration times' do
        freeze_time do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource,
            expires_in: 5.minutes
          )

          approval = result.data[:approval]
          expect(approval.expires_at).to eq(5.minutes.from_now)
        end
      end

      it 'accepts very long expiration times' do
        freeze_time do
          result = described_class.call(
            agent: agent,
            action: action,
            resource: resource,
            expires_in: 30.days
          )

          approval = result.data[:approval]
          expect(approval.expires_at).to eq(30.days.from_now)
        end
      end
    end
  end
end