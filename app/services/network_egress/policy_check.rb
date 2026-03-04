# frozen_string_literal: true

require "ipaddr"
require "uri"

module NetworkEgress
  class PolicyCheck
    Result = Struct.new(:allowed?, :reason, keyword_init: true)

    def self.call(agent:, url:)
      new(agent:, url:).call
    end

    def initialize(agent:, url:)
      @agent = agent
      @url = url
    end

    def call
      policy = @agent.effective_egress_policy
      mode = policy[:mode]

      # No policy or disabled → allow all
      return allow("no egress policy") if mode.blank? || mode == "disabled"

      uri = parse_uri
      return deny("invalid URL: #{@url}") unless uri

      host = uri.host
      port = uri.port

      rules = Array(policy[:rules])

      case mode
      when "allowlist"
        check_allowlist(host, port, rules, policy)
      when "blocklist"
        check_blocklist(host, port, rules, policy)
      else
        allow("unknown mode")
      end
    end

    private

    def check_allowlist(host, port, rules, policy)
      if rules.any? { |rule| matches_rule?(host, port, rule) }
        allow("host matches allowlist")
      else
        result = deny("host '#{host}' not in allowlist")
        log_blocked(host, port, "not in allowlist", policy)
        result
      end
    end

    def check_blocklist(host, port, rules, policy)
      matching_rule = rules.find { |rule| matches_rule?(host, port, rule) }
      if matching_rule
        result = deny("host '#{host}' matches blocklist pattern '#{matching_rule['pattern'] || matching_rule[:pattern]}'")
        log_blocked(host, port, "matches blocklist", policy)
        result
      else
        allow("host not in blocklist")
      end
    end

    def matches_rule?(host, port, rule)
      rule = rule.with_indifferent_access
      pattern = rule[:pattern].to_s.strip
      rule_port = rule[:port]

      return false if rule_port.present? && rule_port.to_i != port

      matches_pattern?(host, pattern)
    end

    def matches_pattern?(host, pattern)
      return false if host.blank? || pattern.blank?

      # CIDR notation check
      if pattern.include?("/")
        return cidr_match?(host, pattern)
      end

      # Glob pattern (*.example.com)
      if pattern.start_with?("*.")
        suffix = pattern[1..] # ".example.com"
        return host == pattern[2..] || host.end_with?(suffix)
      end

      # Exact match
      host.downcase == pattern.downcase
    end

    def cidr_match?(host, cidr)
      ip = IPAddr.new(host)
      network = IPAddr.new(cidr)
      network.include?(ip)
    rescue IPAddr::InvalidAddressError
      false
    end

    def parse_uri
      uri = URI.parse(@url)
      return nil unless uri.host.present?
      uri
    rescue URI::InvalidURIError
      nil
    end

    def allow(reason)
      Result.new(allowed?: true, reason:)
    end

    def deny(reason)
      Result.new(allowed?: false, reason:)
    end

    def log_blocked(host, port, reason, policy)
      return unless policy[:log_blocked]

      AuditLog.record(
        actor_type: "agent",
        actor_id: @agent.id,
        action: "network_egress.blocked",
        metadata: {
          url: @url,
          host:,
          port:,
          reason:,
          policy_mode: policy[:mode]
        }
      )
    end
  end
end
