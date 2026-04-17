# frozen_string_literal: true

module Swarms
  # Immutable value object representing a validated .swarm.json file.
  # Built by SwarmParser after SwarmSchema validation passes.
  #
  # All nested types are also immutable Data.define value objects.
  class SwarmDocument
    SwarmAuthor = Data.define(:name, :url, :email) do
      def self.from_hash(h)
        return nil if h.nil?

        h = h.with_indifferent_access
        new(
          name:  h[:name].presence,
          url:   h[:url].presence,
          email: h[:email].presence
        )
      end
    end

    SwarmRequirements = Data.define(:hivemind_version, :integrations, :provider_models) do
      def self.from_hash(h)
        return nil if h.nil?

        h = h.with_indifferent_access
        new(
          hivemind_version: h[:hivemind_version].presence,
          integrations:     Array(h[:integrations]).map(&:to_s),
          provider_models:  Array(h[:provider_models]).map(&:to_s)
        )
      end
    end

    SwarmTeam = Data.define(:name, :description, :custom_soul) do
      def self.from_hash(h)
        return nil if h.nil?

        h = h.with_indifferent_access
        new(
          name:        h[:name].presence,
          description: h[:description].presence,
          custom_soul: h[:custom_soul].presence
        )
      end
    end

    SwarmVariable = Data.define(:description, :required, :type, :default) do
      def self.from_hash(h)
        h = h.with_indifferent_access
        new(
          description: h[:description].presence,
          required:    h.fetch(:required, false),
          type:        h[:type].presence || "string",
          default:     h[:default]
        )
      end
    end

    attr_reader :swarm_version, :name, :slug, :description, :author, :version,
                :license, :tags, :icon, :homepage, :requires, :team,
                :agents, :skills, :tools, :channels, :mcp_servers,
                :api_integrations, :variables,
                :workspace_files, :scheduled_tasks, :heartbeat_config

    def initialize(swarm_version:, name:, slug: nil, description: nil, author: nil,
                   version: nil, license: nil, tags: nil, icon: nil, homepage: nil,
                   requires: nil, team: nil, agents: nil, skills: nil, tools: nil,
                   channels: nil, mcp_servers: nil, api_integrations: nil, variables: nil,
                   workspace_files: nil, scheduled_tasks: nil, heartbeat_config: nil)
      @swarm_version    = swarm_version
      @name             = name
      @slug             = slug
      @description      = description
      @author           = author
      @version          = version
      @license          = license
      @tags             = Array(tags).freeze
      @icon             = icon
      @homepage         = homepage
      @requires         = requires
      @team             = team
      @agents           = Array(agents).freeze
      @skills           = Array(skills).freeze
      @tools            = Array(tools).freeze
      @channels         = Array(channels).freeze
      @mcp_servers      = Array(mcp_servers).freeze
      @api_integrations = Array(api_integrations).freeze
      @variables        = (variables || {}).freeze
      @workspace_files  = Array(workspace_files).freeze
      @scheduled_tasks  = Array(scheduled_tasks).freeze
      @heartbeat_config = heartbeat_config
      freeze
    end

    def agent_count               = @agents.size
    def skill_count               = @skills.size
    def tool_count                = @tools.size
    def channel_count             = @channels.size
    def mcp_server_count          = @mcp_servers.size
    def api_integration_count     = @api_integrations.size
    def workspace_file_count      = @workspace_files.size
    def scheduled_task_count      = @scheduled_tasks.size
    def heartbeat_config_present? = !@heartbeat_config.nil?
  end
end
