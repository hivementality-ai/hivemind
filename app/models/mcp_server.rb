# frozen_string_literal: true

class McpServer < ApplicationRecord
  TRANSPORTS = %w[stdio sse].freeze
  STATUSES = %w[disconnected connected error].freeze

  has_many :agent_mcp_servers, dependent: :destroy
  has_many :agents, through: :agent_mcp_servers

  validates :name, presence: true, uniqueness: true
  validates :transport, presence: true, inclusion: { in: TRANSPORTS }
  validates :command, presence: true, if: :stdio?
  validates :url, presence: true, if: :sse?

  scope :enabled, -> { where(enabled: true) }
  scope :preset, -> { where(preset: true) }
  scope :by_transport, ->(transport) { where(transport: transport) }
  scope :connected, -> { where(status: "connected") }
  scope :errored, -> { where(status: "error") }

  def stdio?
    transport == "stdio"
  end

  def sse?
    transport == "sse"
  end

  def connected?
    status == "connected"
  end

  def mark_connected!(pid: nil, tools: nil)
    attrs = { status: "connected", last_connected_at: Time.current, last_error: nil }
    attrs[:metadata] = (metadata || {}).merge("pid" => pid) if pid
    if tools
      attrs[:discovered_tools] = tools
      attrs[:tools_refreshed_at] = Time.current
    end
    update!(attrs)
  end

  def mark_error!(message)
    update!(status: "error", last_error: message)
  end

  def mark_disconnected!
    update!(status: "disconnected")
  end

  def update_discovered_tools!(tools)
    update!(discovered_tools: tools, tools_refreshed_at: Time.current)
  end

  def resolved_env_vars
    return {} unless env_vars.present?

    env_vars.each_with_object({}) do |(key, value), resolved|
      resolved[key] = if value.to_s.start_with?("vault:")
        path = value.sub("vault:", "")
        namespace, vault_key = path.split("/", 2)
        entry = VaultEntry.find_by(namespace: namespace, key: vault_key)
        entry&.value || value
      else
        value
      end
    end
  end

  def resolved_auth_headers
    return {} unless auth_config.present?

    auth_config.each_with_object({}) do |(key, value), headers|
      headers[key] = if value.to_s.start_with?("vault:")
        path = value.sub("vault:", "")
        namespace, vault_key = path.split("/", 2)
        entry = VaultEntry.find_by(namespace: namespace, key: vault_key)
        entry&.value || value
      else
        value
      end
    end
  end
end
