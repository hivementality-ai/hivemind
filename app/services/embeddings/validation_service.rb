# frozen_string_literal: true

module Embeddings
  class ValidationService
    SAMPLE_SIZE = 50
    SIMILARITY_THRESHOLD = 0.7

    def initialize(migration_status)
      @status = migration_status
    end

    # Compare search quality between primary and shadow embeddings.
    # Returns a results hash with coverage, quality metrics, and pass/fail.
    def validate
      entries_with_both = MemoryEntry.where.not(embedding: nil).where.not(shadow_embedding: nil)
      total_with_shadow = entries_with_both.count
      total_embedded = MemoryEntry.where.not(embedding: nil).count

      coverage = total_embedded > 0 ? (total_with_shadow.to_f / total_embedded * 100).round(1) : 0

      # Sample entries for quality comparison
      sample = entries_with_both.order("RANDOM()").limit(SAMPLE_SIZE)

      quality_scores = sample.filter_map do |entry|
        compare_search_quality(entry)
      end

      avg_overlap = quality_scores.any? ? (quality_scores.sum / quality_scores.size).round(3) : 0
      pass = coverage >= 95 && avg_overlap >= 0.6

      {
        coverage_percent: coverage,
        total_embedded: total_embedded,
        total_with_shadow: total_with_shadow,
        sample_size: quality_scores.size,
        avg_result_overlap: avg_overlap,
        pass: pass,
        validated_at: Time.current.iso8601
      }
    end

    private

    # For a given entry, compare top-N results from primary vs shadow embedding search.
    # Returns the overlap ratio (0.0 - 1.0).
    def compare_search_quality(entry)
      agent = entry.agent
      return nil unless agent

      # Search using primary embedding
      primary_results = MemoryEntry
        .where(agent: agent)
        .where.not(id: entry.id)
        .nearest_neighbors(:embedding, entry.embedding, distance: "cosine")
        .limit(10)
        .pluck(:id)

      # Search using shadow embedding
      shadow_results = MemoryEntry
        .where(agent: agent)
        .where.not(id: entry.id)
        .where.not(shadow_embedding: nil)
        .nearest_neighbors(:shadow_embedding, entry.shadow_embedding, distance: "cosine")
        .limit(10)
        .pluck(:id)

      return nil if primary_results.empty? || shadow_results.empty?

      # Calculate overlap ratio
      overlap = (primary_results & shadow_results).size
      overlap.to_f / [ primary_results.size, shadow_results.size ].max
    rescue StandardError => e
      Rails.logger.error("[ValidationService] Comparison failed for entry #{entry.id}: #{e.message}")
      nil
    end
  end
end
