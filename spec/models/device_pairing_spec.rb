# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DevicePairing, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:device_id) }
    it { should validate_presence_of(:device_type) }

    it 'validates uniqueness of device_id' do
      create(:device_pairing, device_id: "unique_device_123")
      expect(build(:device_pairing, device_id: "unique_device_123")).not_to be_valid
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(pending: 0, approved: 1, rejected: 2, revoked: 3).with_default(:pending) }
  end

  describe 'scopes' do
    let!(:pending_pairing) { create(:device_pairing, :pending) }
    let!(:approved_pairing) { create(:device_pairing, :approved) }
    let!(:rejected_pairing) { create(:device_pairing, :rejected) }
    let!(:revoked_pairing) { create(:device_pairing, :revoked) }

    describe '.active' do
      it 'returns only approved pairings' do
        expect(DevicePairing.active).to include(approved_pairing)
        expect(DevicePairing.active).not_to include(pending_pairing, rejected_pairing, revoked_pairing)
      end
    end
  end

  describe '#approve!' do
    let(:pairing) { create(:device_pairing, :pending) }

    it 'sets status to approved' do
      pairing.approve!
      expect(pairing.status).to eq("approved")
    end

    it 'sets approved_at to current time' do
      pairing.approve!
      expect(pairing.approved_at).to be_within(1.second).of(Time.current)
    end

    it 'persists the approval' do
      pairing.approve!
      pairing.reload
      expect(pairing.status).to eq("approved")
      expect(pairing.approved_at).to be_present
    end
  end

  describe '#reject!' do
    let(:pairing) { create(:device_pairing, :pending) }

    it 'sets status to rejected' do
      pairing.reject!
      expect(pairing.status).to eq("rejected")
    end

    it 'persists the rejection' do
      pairing.reject!
      pairing.reload
      expect(pairing.status).to eq("rejected")
    end
  end

  describe '#revoke!' do
    let(:pairing) { create(:device_pairing, :approved) }

    it 'sets status to revoked' do
      pairing.revoke!
      expect(pairing.status).to eq("revoked")
    end

    it 'persists the revocation' do
      pairing.revoke!
      pairing.reload
      expect(pairing.status).to eq("revoked")
    end
  end

  describe 'default values' do
    let(:pairing) { DevicePairing.new }

    it 'initializes metadata as empty hash' do
      expect(pairing.metadata).to eq({})
    end
  end

  describe 'factory' do
    it 'creates a valid device pairing' do
      expect(build(:device_pairing)).to be_valid
    end

    it 'creates valid pairings with traits' do
      expect(build(:device_pairing, :pending)).to be_valid
      expect(build(:device_pairing, :approved)).to be_valid
      expect(build(:device_pairing, :rejected)).to be_valid
      expect(build(:device_pairing, :revoked)).to be_valid
      expect(build(:device_pairing, :mobile)).to be_valid
      expect(build(:device_pairing, :desktop)).to be_valid
    end
  end
end
