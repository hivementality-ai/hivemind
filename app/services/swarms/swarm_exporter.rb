# frozen_string_literal: true

module Swarms
  # Orchestrates the full swarm export pipeline end-to-end.
  #
  # Pipeline stages (in order):
  #   1. Serialize team            — TeamSerializer converts the Team record
  #   2. Serialize agents          — AgentSerializer for each agent on the team
  #   3. Serialize skills          — SkillSerializer for all skills referenced by team agents
  #   4. Serialize tools           — ToolSerializer for all tools referenced by team agents
  #   5. Serialize workspace files — WorkspaceFilesSerializer embeds requested files
  #   6. Serialize scheduled tasks — ScheduledTasksSerializer for all agent scheduled tasks
  #   7. Serialize heartbeat config — HeartbeatConfigSerializer captures global heartbeat settings
  #   8. Assemble manifest         — build the top-level .swarm.json Hash with metadata
  #   9. Strip secrets             — SecretStripper replaces sensitive values with vault: refs
  #  10. Validate                  — SwarmSchema.validate confirms output is valid before download
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

    def self.call(team:, author_name: nil, author_email: nil, description: nil,
                  strip_secrets: true, workspace_file_paths: [])
      new(
        team:                 team,
        author_name:          author_name,
        author_email:         author_email,
        description:          description,
        strip_secrets:        strip_secrets,
        workspace_file_paths: workspace_file_paths
      ).call
    end

    def initialize(team:, author_name:, author_email:, description:, strip_secrets:,
                   workspace_file_paths: [])
      @team                 = team
      @author_name          = author_name
      @author_email         = author_email
      @description          = description
      @strip_secrets        = strip_secrets
      @workspace_file_paths = Array(workspace_file_paths)
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

      # Collect scheduled tasks for all agents
      scheduled_task_hashes = collect_scheduled_tasks(agents)

      # Collect workspace files (only if explicit paths were requested)
      workspace_file_hashes = collect_workspace_files

      # Heartbeat config (global — not team-scoped)
      heartbeat_hash = Serializers::HeartbeatConfigSerializer.call

      manifest = {
        "swarm_version" => SWARM_VERSION,
        "name"          => @team.name,
        "exported_at"   => Time.current.utc.iso8601
      }

      manifest["slug"]        = @team.name.parameterize if @team.name.present?
      manifest["description"] = resolved_description
      manifest["author"]      = build_author_hash if author_present?

      manifest["team"]             = team_hash             if team_hash.present?
      manifest["agents"]           = agent_hashes           if agent_hashes.any?
      manifest["skills"]           = skills.map { |s| Serializers::SkillSerializer.call(skill: s) } if skills.any?
      manifest["tools"]            = tools.map  { |t| Serializers::ToolSerializer.call(tool: t) }   if tools.any?
      manifest["scheduled_tasks"]  = scheduled_task_hashes  if scheduled_task_hashes.any?
      manifest["workspace_files"]  = workspace_file_hashes  if workspace_file_hashes.any?
      manifest["heartbeat_config"] = heartbeat_hash          if heartbeat_hash.present?

      manifest.compact
    end

    # Collect all unique skills referenced by the given agents, deduplicated by name.
    def collect_skills(agents)
      seen  = Set.new
      skills = []
      agents.each do |agent|
        agent.skills.order(:name).each do |skill|
          next if seen.include?(skill.name)
          seen  << skill.name
          skills << skill
        end
      end
      skills
    end

    # Collect all unique tools referenced by the given agents, deduplicated by name.
    def collect_tools(agents)
      seen  = Set.new
      tools = []
      agents.each do |agent|
        agent.tools.order(:name).each do |tool|
          next if seen.include?(tool.name)
          seen  << tool.name
          tools << tool
        end
      end
      tools
    end

    # Collect all scheduled tasks for the given agents, in agent-name + task-name order.
    def collect_scheduled_tasks(agents)
      agents.flat_map do |agent|
        agent.scheduled_tasks.order(:name).map do |task|
          Serializers::ScheduledTasksSerializer.call(scheduled_task: task)
        end
      end
    end

    # Serialize any workspace files explicitly requested for export.
    # Returns an empty array when no paths were provided.
    def collect_workspace_files
      return [] if @workspace_file_paths.empty?

      result = Serializers::WorkspaceFilesSerializer.call(paths: @workspace_file_paths)
      return [] unless result.success?

      result.payload[:workspace_files]
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
