# frozen_string_literal: true

class ApiIntegration < ApplicationRecord
  belongs_to :user, optional: true

  validates :name, presence: true, uniqueness: true
  validates :base_url, presence: true, format: { with: /\Ahttps?:\/\//i, message: "must start with http:// or https://" }

  scope :enabled, -> { where(enabled: true) }

  # Auth types: none, api_key, bearer, basic, oauth2
  def auth_type
    auth_config["type"] || "none"
  end

  # Retrieve the API key from vault (encrypted)
  def api_key
    vault_key = auth_config["vault_key"] || "#{name.parameterize}_api_key"
    VaultEntry.resolve(namespace: "api_integrations", key: vault_key)&.value
  end

  # Build auth headers for a request
  def auth_headers
    case auth_type
    when "api_key"
      header_name = auth_config["header_name"] || "X-API-Key"
      key = api_key
      key ? { header_name => key } : {}
    when "bearer"
      key = api_key
      key ? { "Authorization" => "Bearer #{key}" } : {}
    when "basic"
      username = auth_config["username"] || ""
      password = api_key || ""
      encoded = Base64.strict_encode64("#{username}:#{password}")
      { "Authorization" => "Basic #{encoded}" }
    else
      {}
    end
  end

  # All headers for requests (default + auth)
  def request_headers
    (default_headers || {}).merge(auth_headers)
  end

  # Find an endpoint by operation_id or path+method
  def find_endpoint(operation_id: nil, path: nil, method: nil)
    (endpoints || []).find do |ep|
      if operation_id
        ep["operation_id"] == operation_id
      else
        ep["path"] == path && ep["method"]&.downcase == method&.downcase
      end
    end
  end

  # Summary for LLM tool description
  def endpoint_summary
    (endpoints || []).map do |ep|
      "#{ep['method']&.upcase} #{ep['path']} — #{ep['summary'] || ep['operation_id'] || 'No description'}"
    end.join("\n")
  end
end
