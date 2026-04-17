# frozen_string_literal: true

module Swarms
  # Immutable value object representing a validated, parsed .swarm.json file.
  #
  # Fields map directly to the top-level .swarm.json schema:
  #
  #   swarm_version      – "1.0"
  #   name               – human-readable swarm name (required)
  #   slug               – URL-safe identifier (optional)
  #   description        – short description (optional)
  #   author             – SwarmAuthor value object (optional)
  #   version            – swarm content version string (optional)
  #   license            – SPDX license identifier (optional)
  #   tags               – array of string tags
  #   icon               – emoji or icon string (optional)
  #   homepage           – URL string (optional)
  #   requires           – SwarmRequirements value object (optional)
  #   team               – SwarmTeam value object (optional)
  #   agents             – array of raw agent definition hashes (frozen)
  #   skills             – array of raw skill definition hashes (frozen)
  #   tools              – array of raw custom tool definition hashes (frozen)
  #   channels           – array of raw channel config hashes (frozen)
  #   mcp_servers        – array of raw MCP server config hashes (frozen)
  #   api_integrations   – array of raw API integration config hashes (frozen)
  #   variables          – hash of variable_name => SwarmVariable (frozen)
  class SwarmDocument
    CURRENT_VERSION = "1.0"

    attr_reader :swarm_version,
                :name,
                :slug,
                :description,
                :author,
                :version,
                :license,
                :tags,
                :icon,
                :homepage,
                :requires,
                :team,
                :agents,
                :skills,
                :tools,
                :channels,
                :mcp_servers,
                :api_integrations,
                :variables

    def initialize(
      swarm_version:,
      name:,
      slug: nil,
      description: nil,
      author: nil,
      version: nil,
      license: nil,
      tags: [],
      icon: nil,
      homepage: nil,
      requires: nil,
      team: nil,
      agents: [],
      skills: [],
      tools: [],
      channels: [],
      mcp_servers: [],
      api_integrations: [],
      variables: {}
    )
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
      @variables        = Hash(variables).freeze

      freeze
    end

    def agent_count           = agents.length
    def skill_count           = skills.length
    def tool_count            = tools.length
    def channel_count         = channels.length
    def mcp_server_count      = mcp_servers.length
    def api_integration_count = api_integrations.length

    # -----------------------------------------------------------------------
    # Nested value objects
    # -----------------------------------------------------------------------

    SwarmAuthor = Data.define(:name, :url, :email) do
      def self.from_hash(h)
        return nil if h.blank?

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
        return nil if h.blank?

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
        return nil if h.blank?

        h = h.with_indifferent_access
        new(
          name:        h[:name].presence,
          description: h[:description].presence,
          custom_soul: h[:custom_soul].presence
        )
      end
    end

    # Represents a single user-configurable variable definition.
    # The key (variable name) is held by the parent hash in SwarmDocument#variables.
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
  end
end
