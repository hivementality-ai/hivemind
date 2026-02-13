# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApprovalRequest, type: :model do
  describe 'associations' do
    it { should belong_to(:agent) }
  end

  describe 'validations' do
    it { should validate_presence_of(:action) }
    it { should validate_presence_of(:resource) }
    it 'sets requested_at automatically' do
      request = build(:approval_request, requested_at: nil)
      request.valid?
      expect(request.requested_at).to be_present
    end
    it { should validate_inclusion_of(:status).in_array(%w[pending approved rejected expired]) }
  end

  describe 'scopes' do
    let!(:pending_request) { create(:approval_request, :pending) }
    let!(:approved_request) { create(:approval_request, :approved) }
    let!(:rejected_request) { create(:approval_request, :rejected) }
    let!(:expired_request) { create(:approval_request, :expired) }
    let!(:unexpired_request) { create(:approval_request, :pending, expires_at: 1.hour.from_now) }

    describe '.pending' do
      it 'returns only pending requests' do
        expect(ApprovalRequest.pending).to include(pending_request, unexpired_request)
        expect(ApprovalRequest.pending).not_to include(approved_request, rejected_request, expired_request)
      end
    end

    describe '.resolved' do
      it 'returns approved and rejected requests' do
        expect(ApprovalRequest.resolved).to include(approved_request, rejected_request)
        expect(ApprovalRequest.resolved).not_to include(pending_request, expired_request)
      end
    end

    describe '.expired' do
      it 'returns only expired requests' do
        expect(ApprovalRequest.expired).to include(expired_request)
        expect(ApprovalRequest.expired).not_to include(pending_request, approved_request, rejected_request)
      end
    end

    describe '.not_expired' do
      it 'returns requests that have not expired' do
        expect(ApprovalRequest.not_expired).to include(pending_request, unexpired_request)
        expect(ApprovalRequest.not_expired).not_to include(expired_request)
      end
    end
  end

  describe '#pending?' do
    it 'returns true when status is pending' do
      request = build(:approval_request, :pending)
      expect(request.pending?).to be true
    end

    it 'returns false when status is not pending' do
      request = build(:approval_request, :approved)
      expect(request.pending?).to be false
    end
  end

  describe '#approved?' do
    it 'returns true when status is approved' do
      request = build(:approval_request, :approved)
      expect(request.approved?).to be true
    end

    it 'returns false when status is not approved' do
      request = build(:approval_request, :pending)
      expect(request.approved?).to be false
    end
  end

  describe '#rejected?' do
    it 'returns true when status is rejected' do
      request = build(:approval_request, :rejected)
      expect(request.rejected?).to be true
    end

    it 'returns false when status is not rejected' do
      request = build(:approval_request, :pending)
      expect(request.rejected?).to be false
    end
  end

  describe '#expired?' do
    context 'when status is expired' do
      it 'returns true' do
        request = build(:approval_request, :expired)
        expect(request.expired?).to be true
      end
    end

    context 'when expires_at is in the past' do
      it 'returns true' do
        request = build(:approval_request, :pending, expires_at: 1.hour.ago)
        expect(request.expired?).to be true
      end
    end

    context 'when expires_at is in the future' do
      it 'returns false' do
        request = build(:approval_request, :pending, expires_at: 1.hour.from_now)
        expect(request.expired?).to be false
      end
    end

    context 'when expires_at is nil' do
      it 'returns false' do
        request = build(:approval_request, :pending, :no_expiry)
        expect(request.expired?).to be false
      end
    end
  end

  describe '#expire!' do
    let(:request) { create(:approval_request, :pending) }

    it 'sets status to expired' do
      request.expire!
      expect(request.status).to eq("expired")
    end

    it 'sets resolved_at to current time' do
      request.expire!
      expect(request.resolved_at).to be_within(1.second).of(Time.current)
    end

    it 'persists the changes' do
      request.expire!
      request.reload
      expect(request.status).to eq("expired")
      expect(request.resolved_at).to be_present
    end
  end

  describe 'default values on create' do
    let(:request) { ApprovalRequest.new(agent: create(:agent), action: "test", resource: "test") }

    it 'sets requested_at to current time' do
      request.valid?
      expect(request.requested_at).to be_within(1.second).of(Time.current)
    end

    it 'sets expires_at to 24 hours from now' do
      request.valid?
      expect(request.expires_at).to be_within(1.second).of(24.hours.from_now)
    end
  end

  describe 'factory' do
    it 'creates a valid approval request' do
      expect(build(:approval_request)).to be_valid
    end

    it 'creates valid requests with traits' do
      expect(build(:approval_request, :pending)).to be_valid
      expect(build(:approval_request, :approved)).to be_valid
      expect(build(:approval_request, :rejected)).to be_valid
      expect(build(:approval_request, :expired)).to be_valid
      expect(build(:approval_request, :no_expiry)).to be_valid
    end
  end
end
