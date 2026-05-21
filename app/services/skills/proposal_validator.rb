# frozen_string_literal: true

module Skills
  # Validates agent-authored skill proposals against quality guardrails.
  #
  # Guardrails enforced:
  #   - Minimum content length (200 chars)
  #   - At least one meaningful heading (##) present
  #   - No sensitive data patterns (API keys, passwords, secrets)
  #   - Name must be snake_case or hyphen-case, max 60 chars
  #   - Summary must be present and within 150 chars
  #   - Category must be a known value
  class ProposalValidator
    MIN_CONTENT_LENGTH = 200
    MAX_NAME_LENGTH    = 60
    NAME_PATTERN       = /\A[a-z0-9][a-z0-9_\-]*\z/

    # Patterns that signal embedded secrets / sensitive data.
    # These are intentionally simple — the SkillSecurityScanner handles deep analysis.
    SENSITIVE_PATTERNS = [
      /(?:api[_\-]?key|api[_\-]?secret|access[_\-]?token|auth[_\-]?token)\s*[:=]\s*\S+/i,
      /(?:password|passwd|pwd)\s*[:=]\s*\S+/i,
      /(?:secret[_\-]?key|private[_\-]?key)\s*[:=]\s*\S+/i,
      /Bearer\s+[A-Za-z0-9\-._~+\/]{20,}/,
      /ghp_[A-Za-z0-9]{36}/,
      /sk-[A-Za-z0-9]{32,}/
    ].freeze

    def self.call(name:, summary:, content:, category:)
      new(name:, summary:, content:, category:).call
    end

    def initialize(name:, summary:, content:, category:)
      @name     = name.to_s.strip
      @summary  = summary.to_s.strip
      @content  = content.to_s.strip
      @category = category.to_s.strip
      @errors   = []
    end

    def call
      validate_name
      validate_summary
      validate_content_length
      validate_content_structure
      validate_category
      check_sensitive_data

      if @errors.empty?
        ServiceResponse.success(data: { valid: true })
      else
        ServiceResponse.failure(error: @errors.join("; "))
      end
    end

    private

    def validate_name
      if @name.blank?
        @errors << "Name is required"
        return
      end

      @errors << "Name must be #{MAX_NAME_LENGTH} characters or fewer" if @name.length > MAX_NAME_LENGTH
      @errors << "Name must use only lowercase letters, numbers, hyphens, and underscores" unless @name.match?(NAME_PATTERN)
    end

    def validate_summary
      @errors << "Summary is required" if @summary.blank?
      @errors << "Summary must be 150 characters or fewer" if @summary.length > 150
    end

    def validate_content_length
      if @content.length < MIN_CONTENT_LENGTH
        @errors << "Content must be at least #{MIN_CONTENT_LENGTH} characters (got #{@content.length})"
      end
    end

    def validate_content_structure
      return if @content.blank?

      has_heading = @content.match?(/^#{2}\s+\S+/)
      @errors << "Content must contain at least one section heading (## Heading)" unless has_heading
    end

    def validate_category
      return if @category.blank? # optional field — defaults to utilities

      unless Skill::CATEGORIES.include?(@category)
        @errors << "Category '#{@category}' is not valid. Must be one of: #{Skill::CATEGORIES.join(', ')}"
      end
    end

    def check_sensitive_data
      SENSITIVE_PATTERNS.each do |pattern|
        if @content.match?(pattern) || @name.match?(pattern) || @summary.match?(pattern)
          @errors << "Content appears to contain sensitive data (credentials, secrets, or tokens)"
          return # one error is enough
        end
      end
    end
  end
end
