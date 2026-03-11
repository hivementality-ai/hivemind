# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliveryQueueEntry do
  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:agent).optional }
    it { is_expected.to belong_to(:session).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:recipient) }
    it { is_expected.to validate_presence_of(:content) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending sent failed dead_letter]) }
    it { is_expected.to validate_numericality_of(:attempts).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:max_attempts).is_greater_than(0) }
  end

  describe "scopes" do
    let!(:pending_entry) { create(:delivery_queue_entry, status: "pending", next_attempt_at: 1.minute.ago) }
    let!(:sent_entry) { create(:delivery_queue_entry, :sent) }
    let!(:dead_entry) { create(:delivery_queue_entry, :dead_letter) }

    it ".pending returns only pending entries" do
      expect(described_class.pending).to contain_exactly(pending_entry)
    end

    it ".dead_letter returns only dead letter entries" do
      expect(described_class.dead_letter).to contain_exactly(dead_entry)
    end

    it ".due_for_retry returns pending entries with past next_attempt_at" do
      expect(described_class.due_for_retry).to contain_exactly(pending_entry)
    end
  end
end
