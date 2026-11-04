# frozen_string_literal: true

require "ipaddr"
require "uri"

# An HTTP API described as data. Each enabled operation is offered to agents as a
# tool named +connector__<slug>__<operation>+; Connectors::Executor runs it.
# Secrets are never stored here, only "vault:namespace/key" references.
class Connector < ApplicationRecord
  AUTH_SCHEMES = %w[none api_key_header api_key_query bearer basic oauth2].freeze
  HTTP_METHODS = %w[GET POST PUT PATCH DELETE].freeze

  # Non-secret auth_config keys; every other value must be a vault reference.
  PLAIN_AUTH_KEYS = %w[header_name param_name token_url].freeze
  REQUIRED_AUTH_KEYS = {
    "none" => [],
    "api_key_header" => %w[header_name secret],
    "api_key_query" => %w[param_name secret],
    "bearer" => %w[secret],
    "basic" => %w[username password],
    "oauth2" => %w[access_token]
  }.freeze
  OPTIONAL_AUTH_KEYS = { "oauth2" => %w[refresh_token client_id client_secret token_url] }.freeze

  SLUG_FORMAT = /\A[a-z0-9]+(_[a-z0-9]+)*\z/
  OPERATION_NAME_FORMAT = /\A[a-z][a-z0-9]*(_[a-z0-9]+)*\z/
  HEADER_NAME_FORMAT = /\A[A-Za-z0-9-]+\z/
  PARAM_NAME_FORMAT = /\A[A-Za-z0-9_.-]+\z/
  PATH_PLACEHOLDER = /\{([A-Za-z_][A-Za-z0-9_]*)\}/
  LAN_SUFFIXES = %w[.local .lan .home.arpa].freeze

  belongs_to :created_by, polymorphic: true, optional: true
  has_many :agent_connector_exclusions, dependent: :delete_all

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, length: { maximum: 40 },
                   format: { with: SLUG_FORMAT, allow_blank: true }
  validates :auth_scheme, inclusion: { in: AUTH_SCHEMES }
  validate :base_url_is_safe
  validate :auth_config_holds_only_references
  validate :operations_are_well_formed

  # @param host [String] URL host
  # @return [Boolean] true when the host is loopback or a private LAN address or name
  def self.local_host?(host)
    host = host.to_s.delete_prefix("[").delete_suffix("]").downcase
    return true if host == "localhost" || LAN_SUFFIXES.any? { |suffix| host.end_with?(suffix) }

    ip = IPAddr.new(host)
    ip.loopback? || ip.private?
  rescue IPAddr::Error
    false
  end

  # @param name [String] operation name
  # @return [Hash, nil] the operation definition with string keys
  def operation(name)
    operations.find { |op| op["name"] == name.to_s }
  end

  private

  def base_url_is_safe
    return errors.add(:base_url, "can't be blank") if base_url.blank?

    uri = URI.parse(base_url)
    unless %w[http https].include?(uri.scheme) && uri.host.present?
      return errors.add(:base_url, "must be an http(s) URL")
    end
    errors.add(:base_url, "must not contain credentials") if uri.userinfo.present?
    errors.add(:base_url, "must not contain a query or fragment") if uri.query || uri.fragment
    if uri.scheme == "http" && !self.class.local_host?(uri.host)
      errors.add(:base_url, "must use https unless it points at localhost or the local network")
    end
    errors.add(:base_url, "points at a blocked address") if Connectors::AddressGuard.blocked_host?(uri.host)
  rescue URI::InvalidURIError
    errors.add(:base_url, "is not a valid URL")
  end

  def auth_config_holds_only_references
    config = auth_config
    return errors.add(:auth_config, "must be an object") unless config.is_a?(Hash)

    keys = config.keys.map(&:to_s)
    required = REQUIRED_AUTH_KEYS.fetch(auth_scheme.to_s, [])
    allowed = required + OPTIONAL_AUTH_KEYS.fetch(auth_scheme.to_s, [])
    (required - keys).each { |key| errors.add(:auth_config, "is missing #{key}") }
    (keys - allowed).each { |key| errors.add(:auth_config, "has unexpected key #{key}") }
    config.each { |key, value| validate_auth_value(key.to_s, value) if allowed.include?(key.to_s) }
  end

  def validate_auth_value(key, value)
    if PLAIN_AUTH_KEYS.include?(key)
      validate_plain_auth_value(key, value)
    elsif !Vault::Reference.valid?(value)
      errors.add(:auth_config, "#{key} must be a vault reference like vault:namespace/key, never the secret itself")
    end
  end

  def validate_plain_auth_value(key, value)
    errors.add(:auth_config, "#{key} is not valid") unless plain_auth_value_ok?(key, value)
  end

  def plain_auth_value_ok?(key, value)
    return false unless value.is_a?(String)

    case key
    when "header_name" then HEADER_NAME_FORMAT.match?(value)
    when "param_name" then PARAM_NAME_FORMAT.match?(value)
    else value.start_with?("https://")
    end
  end

  def operations_are_well_formed
    return errors.add(:operations, "must be a list") unless operations.is_a?(Array)

    names = operations.filter_map { |op| op["name"] if op.is_a?(Hash) }
    errors.add(:operations, "must have unique names") if names.uniq.size != names.size
    operations.each_with_index { |op, index| validate_operation(op, index) }
  end

  def validate_operation(op, index)
    label = "operation #{index + 1}"
    return errors.add(:operations, "#{label} must be an object") unless op.is_a?(Hash)

    unless op["name"].is_a?(String) && OPERATION_NAME_FORMAT.match?(op["name"]) && op["name"].length <= 40
      errors.add(:operations, "#{label} needs a lowercase snake_case name")
    end
    errors.add(:operations, "#{label} needs a description") if op["description"].blank?
    errors.add(:operations, "#{label} has an unsupported method") unless HTTP_METHODS.include?(op["method"].to_s.upcase)
    errors.add(:operations, "#{label} read_only must be true or false") unless [ true, false ].include?(op["read_only"])
    properties = validate_params_schema(op["params"], label)
    validate_path_template(op["path"], properties, label)
  end

  def validate_params_schema(params, label)
    return {} if params.nil?

    properties = params.is_a?(Hash) ? params.fetch("properties", {}) : nil
    unless params.is_a?(Hash) && params["type"] == "object" && properties.is_a?(Hash)
      errors.add(:operations, "#{label} params must be a JSON schema object")
      return {}
    end
    properties
  end

  def validate_path_template(path, properties, label)
    unless path.is_a?(String) && path.start_with?("/") && !path.start_with?("//")
      return errors.add(:operations, "#{label} path must start with a single /")
    end
    return errors.add(:operations, "#{label} path must stay inside the base URL") if escapes_base?(path)

    path.scan(PATH_PLACEHOLDER).flatten.each do |placeholder|
      next if properties.key?(placeholder)

      errors.add(:operations, "#{label} path uses {#{placeholder}} but params does not define it")
    end
    return unless path.gsub(PATH_PLACEHOLDER, "").match?(/[{}]/)

    errors.add(:operations, "#{label} path has a malformed {placeholder}")
  end

  def escapes_base?(path)
    return true if path.match?(/[?#\\]/) || path.include?("://") || path.downcase.include?("%2f")

    path.split("/").any? { |segment| segment == "." || segment == ".." || segment.downcase.match?(/\A(%2e)+\z/) }
  end
end
