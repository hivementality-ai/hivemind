# frozen_string_literal: true

require "rails_helper"

RSpec.describe Hivemind::Doctor do
  describe ".run_all" do
    it "returns an array of check results" do
      results = described_class.run_all
      expect(results).to be_an(Array)
      expect(results).to all(include(:name, :status))
    end
  end

  describe ".run_all_as_hash" do
    it "returns a hash with timestamp and checks" do
      result = described_class.run_all_as_hash
      expect(result).to include(:timestamp, :healthy, :checks)
    end
  end

  describe ".check_postgresql" do
    it "returns ok when database is connected" do
      results = described_class.check_postgresql
      expect(results.first[:status]).to eq(:ok)
    end
  end

  describe ".check_channels" do
    it "returns warning when no channels configured" do
      results = described_class.check_channels
      expect(results.first[:status]).to eq(:warning)
    end
  end

  describe ".check_delivery_queue" do
    it "returns ok with no entries" do
      results = described_class.check_delivery_queue
      expect(results.first[:status]).to eq(:ok)
    end

    context "with dead letter entries" do
      before { create(:delivery_queue_entry, :dead_letter) }

      it "returns warning" do
        results = described_class.check_delivery_queue
        expect(results.first[:status]).to eq(:warning)
      end
    end
  end
end
