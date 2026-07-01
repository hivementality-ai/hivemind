# frozen_string_literal: true

module Reflection
  # Scores a reflection hash (0.0–1.0) for usefulness.
  #
  # Filters out garbage reflections — empty arrays, single-word entries,
  # pure filler phrases — so only meaningful reflections get persisted.
  #
  # Scoring factors:
  #   - Coverage: how many of the 5 expected sections are non-empty
  #   - Depth: average number of items per section (more = richer)
  #   - Specificity: penalty for generic/filler phrases
  #   - Novel solutions bonus: extra weight when novel_solutions is present
  class QualityScorer
    # Phrases that indicate a low-quality, generic reflection.
    FILLER_PATTERNS = [
      /\btodo\b/i,
      /\bn\/a\b/i,
      /\bnone\b/i,
      /\bnothing\b/i,
      /\bN\/A\b/,
      /\bno issues\b/i,
      /\bwent (fine|smoothly|well|great|ok|okay)\b/i,
      /\ball good\b/i,
      /\bno problems\b/i,
      /\bno surprises\b/i
    ].freeze

    REQUIRED_SECTIONS = %w[went_well was_hard do_differently key_insights].freeze
    BONUS_SECTION     = "novel_solutions"

    def self.score(reflection)
      new(reflection).score
    end

    def initialize(reflection)
      @reflection = reflection.is_a?(Hash) ? reflection : {}
    end

    def score
      return 0.0 if @reflection.empty?

      coverage_score  = compute_coverage
      depth_score     = compute_depth
      specificity_pen = compute_specificity_penalty
      novel_bonus     = compute_novel_bonus

      raw = (coverage_score * 0.4) + (depth_score * 0.4) - (specificity_pen * 0.2) + novel_bonus

      raw.clamp(0.0, 1.0).round(3)
    end

    private

    # What fraction of required sections are non-empty?
    def compute_coverage
      filled = REQUIRED_SECTIONS.count { |k| items_for(k).any? }
      filled.to_f / REQUIRED_SECTIONS.size
    end

    # Normalised average item count across required sections (caps at 3 items per section).
    def compute_depth
      counts = REQUIRED_SECTIONS.map { |k| [items_for(k).size, 3].min }
      return 0.0 if counts.empty?

      avg = counts.sum.to_f / counts.size
      avg / 3.0
    end

    # Fraction of all items that are filler phrases (penalty 0.0–1.0).
    def compute_specificity_penalty
      all_items = all_reflection_items
      return 0.0 if all_items.empty?

      filler_count = all_items.count { |item| filler?(item) }
      filler_count.to_f / all_items.size
    end

    # Small bonus when novel_solutions is non-empty — these drive skill proposals.
    def compute_novel_bonus
      items_for(BONUS_SECTION).any? ? 0.1 : 0.0
    end

    def items_for(key)
      val = @reflection[key]
      val.is_a?(Array) ? val.reject(&:blank?) : []
    end

    def all_reflection_items
      (REQUIRED_SECTIONS + [BONUS_SECTION]).flat_map { |k| items_for(k) }
    end

    def filler?(text)
      text.strip.split.size < 3 ||
        FILLER_PATTERNS.any? { |pat| text.match?(pat) }
    end
  end
end
