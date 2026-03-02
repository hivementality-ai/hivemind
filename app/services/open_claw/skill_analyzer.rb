# frozen_string_literal: true

module OpenClaw
  class SkillAnalyzer
    SUSPICIOUS_PATTERNS = [
      {
        name: "pipe_to_shell",
        pattern: /curl\s+[^\n]*\|\s*(bash|sh)\b/i,
        severity: "critical",
        description: "Downloads and executes remote code via curl pipe to shell"
      },
      {
        name: "wget_pipe_shell",
        pattern: /wget\s+[^\n]*-O\s*-\s*\|\s*(sh|bash)\b/i,
        severity: "critical",
        description: "Downloads and executes remote code via wget pipe to shell"
      },
      {
        name: "eval_call",
        pattern: /\beval\s*\(/,
        severity: "critical",
        description: "Dynamic code evaluation can execute arbitrary code"
      },
      {
        name: "credential_exfil",
        pattern: /(cat|echo|type|head|tail)\s+[^\n]*(\.env|credentials|id_rsa|id_ed25519|\.ssh\/|secrets\.yml|master\.key)/i,
        severity: "critical",
        description: "Attempts to read sensitive credentials or key files"
      },
      {
        name: "prompt_injection",
        pattern: /(<\/SYSTEM>|ignore\s+previous\s+instructions|disregard\s+(all\s+)?prior\s+(instructions|prompts))/i,
        severity: "critical",
        description: "Prompt injection attempt to override system instructions"
      },
      {
        name: "reverse_shell",
        pattern: /\b(nc|ncat|netcat)\s+[^\n]*(-[le]|EXEC)|\bsocat\b[^\n]*EXEC/i,
        severity: "critical",
        description: "Reverse shell attempt to establish remote access"
      },
      {
        name: "base64_decode",
        pattern: /base64\s+(-d|--decode)/i,
        severity: "high",
        description: "Base64 decoding may be used to obfuscate malicious payloads"
      },
      {
        name: "shell_http_combo",
        pattern: nil, # Custom detection logic
        severity: "medium",
        description: "Skill combines shell commands with HTTP requests, which may indicate data exfiltration"
      }
    ].freeze

    SHELL_INDICATORS = /\b(bash|sh|exec|system|`[^`]+`|\$\(|subprocess|os\.system|child_process)\b/i
    HTTP_INDICATORS = /\b(curl|wget|http_request|fetch|https?:\/\/|net\/http|requests\.(get|post))\b/i

    def self.call(content:)
      new(content).call
    end

    def initialize(content)
      @content = content
      @lines = content.lines
    end

    def call
      findings = detect_patterns
      risk_level = determine_risk_level(findings)

      ServiceResponse.success(data: {
        findings: findings,
        risk_level: risk_level,
        scanned_at: Time.current.iso8601,
        patterns_checked: SUSPICIOUS_PATTERNS.size,
        clean: findings.empty?
      })
    rescue StandardError => e
      ServiceResponse.failure(error: "Skill analysis failed: #{e.message}")
    end

    private

    def detect_patterns
      findings = []

      SUSPICIOUS_PATTERNS.each do |pattern_def|
        if pattern_def[:name] == "shell_http_combo"
          findings.concat(detect_shell_http_combo(pattern_def))
        else
          findings.concat(detect_pattern(pattern_def))
        end
      end

      findings
    end

    def detect_pattern(pattern_def)
      findings = []

      @lines.each_with_index do |line, index|
        match = line.match(pattern_def[:pattern])
        next unless match

        findings << {
          name: pattern_def[:name],
          severity: pattern_def[:severity],
          description: pattern_def[:description],
          matched_text: match[0].strip,
          line: index + 1
        }
      end

      findings
    end

    def detect_shell_http_combo(pattern_def)
      has_shell = SHELL_INDICATORS.match?(@content)
      has_http = HTTP_INDICATORS.match?(@content)

      return [] unless has_shell && has_http

      [{
        name: pattern_def[:name],
        severity: pattern_def[:severity],
        description: pattern_def[:description],
        matched_text: "Shell commands combined with HTTP requests",
        line: 1
      }]
    end

    def determine_risk_level(findings)
      return "none" if findings.empty?

      severities = findings.map { |f| f[:severity] }
      return "critical" if severities.include?("critical")
      return "high" if severities.include?("high")

      "medium"
    end
  end
end
