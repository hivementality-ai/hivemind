# frozen_string_literal: true

require "digest"

module OpenClaw
  class MaliciousSkillDetector
    # SHA256 checksums of known malicious skill content.
    # Add checksums here as they are identified.
    BLOCKLIST = Set.new([
      # "abc123..." — description of known malicious skill
    ]).freeze

    # Known malicious skill names.
    # Add names here as they are identified.
    NAME_BLOCKLIST = Set.new([
      # "evil-skill-name"
    ]).freeze

    def self.call(content:, name: nil)
      new(content, name).call
    end

    def initialize(content, name)
      @content = content
      @name = name
    end

    def call
      checksum = Digest::SHA256.hexdigest(@content)
      reasons = []

      reasons << "Content checksum matches known malicious skill" if BLOCKLIST.include?(checksum)
      reasons << "Skill name matches known malicious skill" if @name.present? && NAME_BLOCKLIST.include?(@name.downcase.strip)

      ServiceResponse.success(data: {
        blocked: reasons.any?,
        checksum: checksum,
        reasons: reasons,
        checked_at: Time.current.iso8601
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Malicious skill detection failed: #{e.message}")
    end
  end
end
