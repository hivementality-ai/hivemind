# frozen_string_literal: true

module Swarms
  # Immutable value object representing a parsed .swarm.json file.
  # All data is validated and normalized before being stored here.
  #
  # Structure mirrors the .swarm.json schema:
  #   swarm_version  – format version string (e.g. "1.0")
  #   metadata       – SwarmMetadata (name, description, author, tags)
  #   variables      – array of SwarmVariable (name, description, default, required)
  #   vault_refs     – array of VaultRef (path, description)
  #   agents         – array of AgentDefinition hashes
  #   skills         – array of SkillDefinition hashes
  #   tools          – array of ToolDefinition hashes
  #   channels       – array of ChannelDefinition hashes
  #   mcp_servers    – array of McpServerDefinition hashes
  #   scheduled_tasks – array of ScheduledTaskDefinition hashes
  class SwarmDocument
    CURRENT_VERSION = "1.0"

    attr_reader :swarm_version,
                :metadata,
                :variables,
                :vault_refs,
                :agents,
                :skills,
                :tools,
                :channels,
                :mcp_servers,
                :scheduled_tasks

    def initialize(
      swarm_version:,
      metadata:,
      variables: [],
      vault_refs: [],
      agents: [],
      skills: [],
      tools: [],
      channels: [],
      mcp_servers: [],
      scheduled_tasks: []
    )
      @swarm_version     = swarm_version
      @metadata          = metadata
      @variables         = Array(variables).freeze
      @vault_refs        = Array(vault_refs).freeze
      @agents            = Array(agents).freeze
      @skills            = Array(skills).freeze
      @tools             = Array(tools).freeze
      @channels          = Array(channels).freeze
      @mcp_servers       = Array(mcp_servers).freeze
      @scheduled_tasks   = Array(scheduled_tasks).freeze

      freeze
    end

    def agent_count = agents.length
    def skill_count = skills.length
    def tool_count  = tools.length

    # -------------------------------------------------------------------
    # Nested value objects
    # -------------------------------------------------------------------

    SwarmMetadata = Data.define(:name, :description, :author, :tags, :exported_at) do
      def self.from_hash(h)
        h = h.with_indifferent_access
        new(
          name:        h.fetch(:name),
          description: h[:description].presence,
          author:      h[:author].presence,
          tags:        Array(h[:tags]).map(&:to_s),
          exported_at: h[:exported_at].presence
        )
      end
    end

    SwarmVariable = Data.define(:name, :description, :default, :required) do
      def self.from_hash(h)
        h = h.with_indifferent_access
        new(
          name:        h.fetch(:name),
          description: h[:description].presence,
          default:     h[:default],
          required:    h.fetch(:required, false)
        )
      end
    end

    VaultRef = Data.define(:path, :description) do
      def self.from_hash(h)
        h = h.with_indifferent_access
        new(
          path:        h.fetch(:path),
          description: h[:description].presence
        )
      end
    end
  end
end
