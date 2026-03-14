# frozen_string_literal: true

require "rails_helper"

RSpec.describe EmbeddingMigrationStatus, type: :model do
  describe "validations" do
    it "requires from_provider" do
      status = described_class.new(to_provider: "gemini", phase: "shadow")
      expect(status).not_to be_valid
      expect(status.errors[:from_provider]).to be_present
    end

    it "requires to_provider" do
      status = described_class.new(from_provider: "ollama", phase: "shadow")
      expect(status).not_to be_valid
      expect(status.errors[:to_provider]).to be_present
    end

    it "validates phase inclusion" do
      status = described_class.new(from_provider: "ollama", to_provider: "gemini", phase: "invalid")
      expect(status).not_to be_valid
      expect(status.errors[:phase]).to be_present
    end

    it "accepts all valid phases" do
      EmbeddingMigrationStatus::PHASES.each do |phase|
        status = described_class.new(from_provider: "ollama", to_provider: "gemini", phase: phase)
        expect(status).to be_valid
      end
    end
  end

  describe "#active?" do
    it "returns true for shadow phase" do
      status = described_class.new(phase: "shadow")
      expect(status.active?).to be true
    end

    it "returns true for validated phase" do
      status = described_class.new(phase: "validated")
      expect(status.active?).to be true
    end

    it "returns false for complete phase" do
      status = described_class.new(phase: "complete")
      expect(status.active?).to be false
    end

    it "returns false for rolled_back phase" do
      status = described_class.new(phase: "rolled_back")
      expect(status.active?).to be false
    end
  end

  describe ".active scope" do
    it "returns only active migration statuses" do
      active = described_class.create!(from_provider: "ollama", to_provider: "gemini", phase: "shadow")
      described_class.create!(from_provider: "ollama", to_provider: "gemini", phase: "complete")

      expect(described_class.active).to contain_exactly(active)
    end
  end
end
