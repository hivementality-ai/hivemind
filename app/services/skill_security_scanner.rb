# frozen_string_literal: true

class SkillSecurityScanner
  def self.call(content:, name: nil, source: "import")
    new(content, name, source).call
  end

  def initialize(content, name, source)
    @content = content
    @name = name
    @source = source
  end

  def call
    analysis = OpenClaw::SkillAnalyzer.call(content: @content)
    return analysis unless analysis.success?

    detection = OpenClaw::MaliciousSkillDetector.call(content: @content, name: @name)
    return detection unless detection.success?

    findings = analysis.data[:findings]
    blocked = detection.data[:blocked]
    status = determine_status(findings, blocked)

    ServiceResponse.success(data: {
      status: status,
      risk_level: analysis.data[:risk_level],
      blocked: blocked,
      findings: findings,
      blocklist_reasons: detection.data[:reasons],
      checksum: detection.data[:checksum],
      source: @source,
      scanned_at: Time.current.iso8601,
      patterns_checked: analysis.data[:patterns_checked]
    })
  rescue StandardError => e
    ServiceResponse.failure(error: "Security scan failed: #{e.message}")
  end

  private

  def determine_status(findings, blocked)
    return "blocked" if blocked

    severities = findings.map { |f| f[:severity] }
    return "flagged" if severities.include?("critical")
    return "warning" if severities.include?("high") || severities.include?("medium")

    "clean"
  end
end
