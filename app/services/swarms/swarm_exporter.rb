# frozen_string_literal: true

module Swarms
  # Orchestrates the full swarm export pipeline end-to-end.
  #
  # Pipeline stages (in order):
  #   1. Serialize team      — TeamSerializer converts the Team record
  #   2. Serialize agents    — AgentSerializer for each agent on the team
  #   3. Serialize skills    — SkillSerializer for all skills referenced by team agents
  #   4. Serialize tools     — ToolSerializer for all tools referenced by team agents
  #   5. Assemble manifest   — build the top-level .swarm.json Hash with metadata
  #   6. Strip secrets       — SecretStripper replaces sensitive values with vault: refs
  #   7. Validate            — SwarmSchema.validate confirms output is valid before download
  #
  # The exporter gathers associated entities by walking the team's agents. Skills
  # and tools are deduplicated by name so each only appears once in the output.
  #
  # Usage:
  #   result = SwarmExporter.call(
  #     team:        team_record,
  #     author_name: "Alice",             # optional — metadata override
  #     author_email: "alice@example.com", # optional
  #     description: "My custom team",    # optional — overrides team.description
  #     strip_secrets: true               # default true
  #   )
  #   result.success?                     # => true / false
  #   result.payload[:manifest]           # => Hash — the full .swarm.json structure
  #   result.payload[:json]               # => String — pretty-printed JSON
  #   result.payload[:filename]           # => String — suggested filename
  #   result.payload[:stripped_paths]     # => Array<String> — secrets that were replaced
  #
  # On failure:
  #   result.error?           # => true
  #   result.message          # => human-readable error
  #   result.payload[:errors] # => Array<String> (validation errors only)
  #
  class SwarmExporter
    SWARM_VERSION = "1.0"

    def self.call(team:, author_name: nil, author_email: nil, description: nil, strip_secrets: true)
      new(
        team:          team,
        author_name:   author_name,
        author_email:  author_email,
        description:   description,
        strip_secrets: strip_secrets
      ).call
    end

    def initialize(team:, author_name:, author_email:, description:, strip_secrets:)
      @team          = team
      @author_name   = author_name
      @author_email  = author_email
      @description   = description
      @strip_secrets = strip_secrets
    end

    def call
      # Stage 1–4: serialize all entities
      manifest = assemble_manifest

      # Stage 6: strip secrets (optional but default-on)
      stripped_paths = []
      if @strip_secrets
        strip_result   = SecretStripper.call(manifest: manifest)
        manifest       = strip_result.payload[:manifest]
        stripped_paths = strip_result.payload[:stripped_paths]
      end

      # Stage 7: validate the assembled manifest before delivering it
      validation = SwarmSchema.validate(manifest)
      unless validation.valid?
        return ServiceResponse.error(
          message: "Export produced invalid swarm document: #{validation.errors.first}",
          payload: { errors: validation.errors }
        )
      end

      json     = JSON.pretty_generate(manifest)
      filename = build_filename

      ServiceResponse.success(
        payload: {
          manifest:       manifest,
          json:           json,
          filename:       filename,
          stripped_paths: stripped_paths
        }
      )
    rescue StandardError => e
      ServiceResponse.error(message: "Export failed: #{e.message}")
    end

    private

    # -------------------------------------------------------------------------
    # Assemble
    # -------------------------------------------------------------------------

    def assemble_manifest
      agents = @team.agents.includes(:skills, :tools).order(:name).to_a

      team_hash    = Serializers::TeamSerializer.call(team: @team)
      agent_hashes = agents.map { |a| Serializers::AgentSerializer.call(agent: a) }

      # Collect unique skills and tools across all agents (by name, preserving order)
      skills = collect_skills(agents)
      tools  = collect_tools(agents)

      # Collect platform-wide entity lists (channels, MCP servers, and API integrations
      # are platform-scoped, not team-scoped — export all enabled records).
      channels         = Channel.order(:name).to_a
      mcp_servers      = McpServer.order(:name).to_a
      api_integrations = ApiIntegration.order(:name).to_a

      manifest = {
        "swarm_version" => SWARM_VERSION,
        "name"          => @team.name,
        "exported_at"   => Time.current.utc.iso8601
      }

      manifest["slug"]        = @team.name.parameterize if @team.name.present?
      manifest["description"] = resolved_description
      manifest["author"]      = build_author_hash if author_present?

      manifest["team"]   = team_hash    if team_hash.present?
      manifest["agents"] = agent_hashes if agent_hashes.any?
      manifest["skills"] = skills.map { |s| Serializers::SkillSerializer.call(skill: s) }                         if skills.any?
      manifest["tools"]  = tools.map  { |t| Serializers::ToolSerializer.call(tool: t) }                          if tools.any?
      manifest["channels"]         = channels.map         { |c| Serializers::ChannelSerializer.call(channel: c) }                         if channels.any?
      manifest["mcp_servers"]      = mcp_servers.map      { |s| Serializers::McpServerSerializer.call(mcp_server: s) }                    if mcp_servers.any?
      manifest["api_integrations"] = api_integrations.map { |i| Serializers::ApiIntegrationSerializer.call(api_integration: i) }          if api_integrations.any?

      manifest.compact
    end

    # Collect all unique skills referenced by the given agents, deduplicated by name.
    # Uses sort_by on the already-eager-loaded association to avoid N+1 queries.
    def collect_skills(agents)
      seen   = Set.new
      skills = []
      agents.each do |agent|
        agent.skills.sort_by(&:name).each do |skill|
          next if seen.include?(skill.name)
          seen   << skill.name
          skills << skill
        end
      end
      skills
    end

    # Collect all unique tools referenced by the given agents, deduplicated by name.
    # Uses sort_by on the already-eager-loaded association to avoid N+1 queries.
    def collect_tools(agents)
      seen  = Set.new
      tools = []
      agents.each do |agent|
        agent.tools.sort_by(&:name).each do |tool|
          next if seen.include?(tool.name)
          seen  << tool.name
          tools << tool
        end
      end
      tools
    end

    # -------------------------------------------------------------------------
    # Metadata helpers
    # -------------------------------------------------------------------------

    def resolved_description
      @description.presence || @team.description.presence
    end

    # Only emit an author block when name is present — schema requires author.name.
    # Email alone is not sufficient; skip the block if name is absent.
    def author_present?
      @author_name.present?
    end

    def build_author_hash
      hash = { "name" => @author_name }
      hash["email"] = @author_email if @author_email.present?
      hash
    end

    def build_filename
      base = @team.name.parameterize(separator: "_")
      "#{base}.swarm.json"
    end
  end
end
