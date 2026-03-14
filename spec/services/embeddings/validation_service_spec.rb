# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeddings::ValidationService, type: :service do
  let(:agent) { create(:agent) }
  let(:status) do
    EmbeddingMigrationStatus.create!(
      from_provider: "ollama", to_provider: "gemini", phase: "shadow", started_at: Time.current
    )
  end

  describe "#validate" do
    it "returns coverage and quality metrics" do
      # Create entries with both embeddings
      3.times do |i|
        MemoryEntry.create!(
          agent: agent,
          content: "memory #{i}",
          memory_type: "semantic",
          embedding: Array.new(768) { rand },
          shadow_embedding: Array.new(768) { rand }
        )
      end

      service = described_class.new(status)
      results = service.validate

      expect(results).to have_key(:coverage_percent)
      expect(results).to have_key(:total_embedded)
      expect(results).to have_key(:total_with_shadow)
      expect(results).to have_key(:sample_size)
      expect(results).to have_key(:avg_result_overlap)
      expect(results).to have_key(:pass)
      expect(results).to have_key(:validated_at)
      expect(results[:coverage_percent]).to eq(100.0)
    end

    it "reports low coverage when shadow embeddings are missing" do
      2.times do |i|
        MemoryEntry.create!(
          agent: agent,
          content: "with shadow #{i}",
          memory_type: "semantic",
          embedding: Array.new(768) { rand },
          shadow_embedding: Array.new(768) { rand }
        )
      end

      2.times do |i|
        MemoryEntry.create!(
          agent: agent,
          content: "without shadow #{i}",
          memory_type: "semantic",
          embedding: Array.new(768) { rand }
        )
      end

      service = described_class.new(status)
      results = service.validate

      expect(results[:coverage_percent]).to eq(50.0)
      expect(results[:total_embedded]).to eq(4)
      expect(results[:total_with_shadow]).to eq(2)
    end

    it "handles zero entries gracefully" do
      service = described_class.new(status)
      results = service.validate

      expect(results[:coverage_percent]).to eq(0)
      expect(results[:pass]).to be false
    end
  end
end
