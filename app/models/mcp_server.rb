# frozen_string_literal: true

class McpServer < ApplicationRecord
  TRANSPORTS = %w[stdio sse http].freeze
  STATUSES = %w[disconnected connected error].freeze

  has_many :agent_mcp_servers, dependent: :destroy
  has_many :agents, through: :agent_mcp_servers

  validates :name, presence: true, uniqueness: true
  validates :transport, presence: true, inclusion: { in: TRANSPORTS }
  validates :command, presence: true, if: :stdio?
  validates :url, presence: true, if: :remote?

  after_destroy { VaultEntry.where(namespace: "mcp_oauth_#{id}").delete_all }

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

  def http?
    transport == "http"
  end

  # Remote servers reached over Streamable HTTP; "sse" is the legacy name for the same transport.
  def remote?
    sse? || http?
  end

  def connected?
    status == "connected"
  end

  # Gives every visible agent this server's tools; assignment is opt-in, so an unassigned server reaches no agent.
  def assign_to_visible_agents!
    Agent.visible.where.not(id: agent_mcp_servers.select(:agent_id)).find_each { |agent| agent_mcp_servers.create!(agent: agent) }
  end

  # @return [String, nil] the OAuth client id set by hand, which skips dynamic client registration
  def oauth_client_id
    metadata.to_h["oauth_client_id"].presence
  end

  # @return [String, nil] the hand-set OAuth client secret, read from the vault
  def oauth_client_secret
    ref = metadata.to_h["oauth_client_secret"].to_s
    return ref.presence unless ref.start_with?("vault:")

    namespace, vault_key = ref.delete_prefix("vault:").split("/", 2)
    VaultEntry.find_by(namespace: namespace, key: vault_key)&.value
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

  # @return [Array<String>] the command's arguments with "vault:" references replaced by the vaulted values; never log it
  def resolved_command_args
    Mcp::CommandSecrets.resolve(command)
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
