# frozen_string_literal: true

module Skills
  # Scores a skill's relevance against a text context.
  #
  # Scoring algorithm:
  #   - Tag match: each tag found in the context contributes a base weight.
  #   - Trigger pattern match: each regex pattern that matches contributes a
  #     higher weight (patterns are more specific than tags).
  #   - Score is normalized to [0.0, 1.0].
  #   - Multiple matches compound up to the ceiling.
  #
  # Usage:
  #   Skills::RelevanceScorer.score(skill: skill, context: "I need to open a PR on GitHub")
  #   # => 0.85
  #
  #   Skills::RelevanceScorer.rank(skills: agent.skills.enabled, context: text, threshold: 0.3)
  #   # => [{ skill: <Skill>, score: 0.85 }, ...]
  class RelevanceScorer
    TAG_WEIGHT     = 0.25   # per matching tag
    PATTERN_WEIGHT = 0.50   # per matching trigger pattern
    MAX_SCORE      = 1.0

    # Returns a score (0.0–1.0) for a single skill vs context text.
    def self.score(skill:, context:)
      new(skill: skill, context: context).call
    end

    # Returns an array of { skill:, score: } hashes, sorted descending,
    # filtered to those at or above the threshold.
    def self.rank(skills:, context:, threshold: 0.3)
      return [] if context.blank?

      skills
        .map { |s| { skill: s, score: new(skill: s, context: context).call } }
        .select { |r| r[:score] >= threshold }
        .sort_by { |r| -r[:score] }
    end

    def initialize(skill:, context:)
      @skill   = skill
      @context = context.to_s.downcase
    end

    def call
      return 0.0 if @context.blank?

      tag_score     = compute_tag_score
      pattern_score = compute_pattern_score
      raw = tag_score + pattern_score

      [raw, MAX_SCORE].min.round(3)
    end

    private

    def compute_tag_score
      return 0.0 if @skill.tags.blank?

      matching = @skill.tags.count { |tag| @context.include?(tag.downcase) }
      matching * TAG_WEIGHT
    end

    def compute_pattern_score
      return 0.0 if @skill.trigger_patterns.blank?

      matching = @skill.trigger_patterns.count do |pattern|
        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        regex.match?(@context)
      rescue RegexpError
        false
      end

      matching * PATTERN_WEIGHT
    end
  end
end
