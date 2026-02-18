# frozen_string_literal: true

module Vault
  # Redacts sensitive values for safe display to agents and users.
  # Shows recognizable prefix + last 4 characters, masks everything else.
  #
  # Examples:
  #   Vault::Redactor.redact("sk-proj-abc123xyz789def456")  → "sk-••••••••••f456"
  #   Vault::Redactor.redact("AC1234567890abcdef")          → "AC••••••••••cdef"
  #   Vault::Redactor.redact("short")                       → "•••rt"
  class Redactor
    # Order matters — longer/more specific prefixes first
    KNOWN_PREFIXES = [
      { pattern: /\Ask-ant-/, length: 7 },    # Anthropic (before sk-)
      { pattern: /\Ask-proj-/, length: 8 },   # OpenAI project key (before sk-)
      { pattern: /\Ask-/, length: 3 },         # OpenAI generic
      { pattern: /\AAIza/, length: 4 },       # Google API
      { pattern: /\AAC/, length: 2 },         # Twilio Account SID
      { pattern: /\ASK/, length: 2 },         # Twilio API Key
      { pattern: /\Axoxb-/, length: 5 },      # Slack bot token
      { pattern: /\Axoxp-/, length: 5 },      # Slack user token
      { pattern: /\Aghp_/, length: 4 },       # GitHub PAT
      { pattern: /\Aghs_/, length: 4 },       # GitHub App token
      { pattern: /\Aglpat-/, length: 6 },     # GitLab PAT
      { pattern: /\Awhsec_/, length: 6 },     # Webhook secret
      { pattern: /\A\+1/, length: 2 },        # US phone number
      { pattern: /\A\+/, length: 1 },         # International phone number
    ].freeze

    VISIBLE_SUFFIX = 4
    MASK = "•"
    MIN_MASK_LENGTH = 4

    # Redact a sensitive value for display
    # @param value [String] The full secret value
    # @return [String] Redacted string with prefix + mask + last 4 chars
    def self.redact(value)
      return "••••" if value.nil? || value.to_s.strip.empty?

      val = value.to_s
      return MASK * val.length if val.length <= VISIBLE_SUFFIX

      prefix = detect_prefix(val)
      suffix = val[-VISIBLE_SUFFIX..]
      mask_len = [val.length - prefix.length - VISIBLE_SUFFIX, MIN_MASK_LENGTH].max

      "#{prefix}#{MASK * mask_len}#{suffix}"
    end

    # Check if a value looks like a known credential format
    # @param value [String] The value to check
    # @return [String, nil] Description of what it looks like, or nil
    def self.identify(value)
      return nil if value.nil? || value.to_s.strip.empty?

      val = value.to_s
      case val
      when /\Ask-proj-/ then "OpenAI project API key"
      when /\Ask-/      then "OpenAI API key"
      when /\Ask-ant-/  then "Anthropic API key"
      when /\AAC/       then "Twilio Account SID"
      when /\ASK/       then "Twilio API key"
      when /\AAIza/     then "Google API key"
      when /\Axoxb-/    then "Slack bot token"
      when /\Aghp_/     then "GitHub personal access token"
      when /\Aglpat-/   then "GitLab personal access token"
      when /\A\+\d{10,}/ then "Phone number"
      else nil
      end
    end

    def self.detect_prefix(value)
      KNOWN_PREFIXES.each do |entry|
        return value[0...entry[:length]] if value.match?(entry[:pattern])
      end
      ""
    end

    private_class_method :detect_prefix
  end
end
