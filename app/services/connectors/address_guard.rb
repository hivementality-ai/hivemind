# frozen_string_literal: true

require "ipaddr"
require "socket"

module Connectors
  # Refuses addresses a connector must never reach: cloud metadata endpoints and
  # the link-local range around them.
  class AddressGuard
    class Blocked < StandardError; end

    BLOCKED_RANGES = %w[
      169.254.0.0/16
      fe80::/10
      fd00:ec2::/32
      100.100.100.200/32
      168.63.129.16/32
      192.0.0.192/32
      0.0.0.0/8
      ::/128
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    BLOCKED_NAMES = %w[
      metadata
      metadata.google.internal
      instance-data
      instance-data.ec2.internal
    ].freeze

    # @param host [String] URL host, a name or an IP literal
    # @return [Boolean] true when the host itself is a blocked name or address
    def self.blocked_host?(host)
      host = host.to_s.delete_prefix("[").delete_suffix("]").downcase.chomp(".")
      return true if BLOCKED_NAMES.include?(host)

      blocked_ip?(host)
    end

    # @param address [String, IPAddr] an IP address
    # @return [Boolean] true when the address is blocked
    def self.blocked_ip?(address)
      ip = address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
      ip = ip.native
      BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
    rescue IPAddr::Error
      false
    end

    # Resolves a host and rejects it when any answer is blocked.
    #
    # @param host [String] URL host
    # @return [Array<String>] the resolved addresses, all of them allowed
    # @raise [Blocked] when the host or any resolved address is blocked or unresolvable
    def self.resolve!(host)
      raise Blocked, "Host #{host} is a blocked address" if blocked_host?(host)

      addresses = lookup(host)
      raise Blocked, "Host #{host} did not resolve" if addresses.empty?
      raise Blocked, "Host #{host} resolves to a blocked address" if addresses.any? { |a| blocked_ip?(a) }

      addresses
    end

    # @param host [String] URL host
    # @return [Array<String>] resolved IP addresses
    def self.lookup(host)
      Addrinfo.getaddrinfo(host.to_s.delete_prefix("[").delete_suffix("]"), nil, nil, :STREAM).map(&:ip_address).uniq
    rescue SocketError
      []
    end
  end
end
