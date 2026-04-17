# frozen_string_literal: true

module Swarms
  # Orchestrates the full swarm import pipeline end-to-end.
  #
  # Pipeline stages (in order):
  #   1. Parse & validate   — SwarmParser reads the .swarm.json and validates structure
  #   2. Resolve variables  — VariableResolver substitutes {{VAR}} placeholders
  #   3. Scan vault refs    — VaultReferenceScanner checks vault: prefixes exist
  #   4. Detect conflicts   — SwarmConflictDetector finds name collisions
  #   5. Deploy entities    — team → skills → tools → agents (order matters for FK refs)
  #   6. Build report       — ImportReport summarises every outcome
  #
  # Stages 1–3 are hard failures: a parse error, missing required variable, or
  # missing vault entry stops the pipeline immediately.
  #
  # Stage 4 (conflict detection) is informational: conflicts are resolved via
  # the `resolutions:` parameter. Unresolved conflicts default to :skip.
  #
  # The entire deploy (stage 5) runs inside an ActiveRecord transaction so a
  # failure on any deployer rolls back all prior writes cleanly.
  #
  # Usage:
  #   result = SwarmImporter.call(
  #     path:        "/uploads/team.swarm.json",   # or json:
  #     json:        raw_json_string,               # or path:
  #     variable_overrides: { "API_URL" => "…" },  # optional
  #     resolutions: { "My Agent" => :overwrite }   # optional
  #   )
  #   result.success?         # => true / false
  #   result.payload[:report] # => ImportReport
  #   result.message          # => human-readable error on failure
  #
  # On failure at any pre-deploy stage:
  #   result.error?                        # => true
  #   result.payload[:stage]               # => :parse | :variables | :vault
  #   result.payload[:errors]              # => Array<String> (parse errors only)
  #   result.payload[:missing]             # => Array<String> (variables / vault)
  #
  class SwarmImporter
    # -------------------------------------------------------------------------
    # ImportReport — summary of everything that happened during the import
    # -------------------------------------------------------------------------

    # Outcome for a single deployed entity.
    EntityResult = Data.define(:entity_type, :name, :action, :record) do
      # entity_type – one of :team, :skill, :tool, :agent
      # action      – one of :created, :updated, :skipped, :renamed
    end

    # Full import summary returned in result.payload[:report].
    ImportReport = Data.define(
      :document,
      :entity_results,
      :warnings,
      :variable_overrides_applied,
      :vault_refs_checked
    ) do
      # document                   – SwarmDocument that was imported
      # entity_results             – Array<EntityResult> in deploy order
      # warnings                   – Array<String> informational messages
      # variable_overrides_applied – Hash of variable values that were substituted
      # vault_refs_checked         – Array<String> vault paths that were verified

      def created   = entity_results.select { |r| r.action == :created }
      def updated   = entity_results.select { |r| r.action == :updated }
      def skipped   = entity_results.select { |r| r.action == :skipped }
      def renamed   = entity_results.select { |r| r.action == :renamed }

      def created_count = created.size
      def updated_count = updated.size
      def skipped_count = skipped.size
      def renamed_count = renamed.size
      def total_count   = entity_results.size

      def results_for(entity_type)
        entity_results.select { |r| r.entity_type == entity_type.to_sym }
      end

      # Human-readable summary line, e.g. "3 created, 1 updated, 2 skipped"
      def summary
        parts = []
        parts << "#{created_count} created"  if created_count > 0
        parts << "#{updated_count} updated"  if updated_count > 0
        parts << "#{renamed_count} renamed"  if renamed_count > 0
        parts << "#{skipped_count} skipped"  if skipped_count > 0
        parts.empty? ? "nothing deployed" : parts.join(", ")
      end
    end

    # Outcome for a single deployed workspace file.
    WorkspaceFileResult = Data.define(:path, :action)

    # Outcome for heartbeat config deployment.
    HeartbeatConfigResult = Data.define(:action)

    # -------------------------------------------------------------------------
    # Entry point
    # -------------------------------------------------------------------------

    def self.call(path: nil, json: nil, variable_overrides: {}, resolutions: {})
      new(
        path:               path,
        json:               json,
        variable_overrides: variable_overrides,
        resolutions:        resolutions
      ).call
    end

    def initialize(path: nil, json: nil, variable_overrides: {}, resolutions: {})
      @path               = path
      @json               = json
      @variable_overrides = (variable_overrides || {}).stringify_keys
      @resolutions        = (resolutions || {}).with_indifferent_access
    end

    def call
      # Stage 1: parse & validate
      parse_result = SwarmParser.call(path: @path, json: @json)
      unless parse_result.success?
        return ServiceResponse.error(
          message: parse_result.message,
          payload: { stage: :parse, errors: parse_result.payload&.dig(:errors) || [] }
        )
      end

      document = parse_result.payload

      # Stage 2: resolve variables
      resolver_result = VariableResolver.call(document: document, overrides: @variable_overrides)
      unless resolver_result.success?
        return ServiceResponse.error(
          message: resolver_result.message,
          payload: { stage: :variables, missing: resolver_result.payload[:missing] }
        )
      end

      resolved_manifest          = resolver_result.payload[:manifest]
      variable_overrides_applied = resolver_result.payload[:resolved]

      # Rebuild document from resolved manifest so downstream stages work with
      # substituted values.
      document = rebuild_document(document, resolved_manifest)

      # Stage 3: scan vault references
      vault_result = VaultReferenceScanner.call(manifest: resolved_manifest)
      unless vault_result.success?
        return ServiceResponse.error(
          message: vault_result.message,
          payload: { stage: :vault, missing: vault_result.payload[:missing] }
        )
      end

      vault_refs_checked = vault_result.payload[:vault_refs]

      # Stage 4: detect conflicts (informational — always continues)
      conflict_result = SwarmConflictDetector.call(document: document)
      conflict_report = conflict_result.payload
      warnings        = build_conflict_warnings(conflict_report)

      # Stage 5: deploy entities in a transaction
      entity_results = nil

      ActiveRecord::Base.transaction do
        entity_results = deploy_all(document)
      end

      # Stage 5b: deploy workspace files, scheduled tasks, heartbeat config
      # (outside the AR transaction — filesystem writes and Setting updates)
      workspace_file_results  = deploy_workspace_files(document)
      scheduled_task_results  = deploy_scheduled_tasks(document)
      heartbeat_config_result = deploy_heartbeat_config(document)

      warnings.concat(workspace_file_results.select { |r| r.action == :skipped }.map { |r| "Workspace file skipped (unsafe path): #{r.path}" })
      warnings.concat(scheduled_task_results.select { |r| r.action == :agent_missing }.map { |r| "Scheduled task '#{r.name}' skipped — agent not found" })

      # Stage 6: build and return the import report
      report = ImportReport.new(
        document:                   document,
        entity_results:             entity_results + scheduled_task_results_as_entity_results(scheduled_task_results),
        warnings:                   warnings,
        variable_overrides_applied: variable_overrides_applied,
        vault_refs_checked:         vault_refs_checked
      )

      ServiceResponse.success(payload: { report: report })
    rescue ActiveRecord::RecordInvalid => e
      ServiceResponse.error(
        message: "Deploy failed: #{e.record.errors.full_messages.join(', ')}",
        payload: { stage: :deploy }
      )
    rescue RuntimeError => e
      ServiceResponse.error(
        message: e.message,
        payload: { stage: :deploy }
      )
    end

    private

    # -------------------------------------------------------------------------
    # Deploy stages
    # -------------------------------------------------------------------------

    # Deploy all entity types in dependency order and collect EntityResult objects.
    # Must be called inside an ActiveRecord::Base.transaction block.
    def deploy_all(document)
      results = []

      # Team first — agents need the team record.
      team_result = Deployers::TeamDeployer.call(
        document:    document,
        resolutions: @resolutions
      )
      raise deploy_error("team", team_result) unless team_result.success?

      team_deploy = team_result.payload[:team]
      if team_deploy
        results << EntityResult.new(
          entity_type: :team,
          name:        team_deploy.name,
          action:      team_deploy.action,
          record:      team_deploy.record
        )
      end

      team_record = team_deploy&.record

      # Skills — agents reference skills by name.
      skills_result = Deployers::SkillsDeployer.call(
        document:    document,
        resolutions: @resolutions
      )
      raise deploy_error("skills", skills_result) unless skills_result.success?

      skills_result.payload[:skills].each do |dr|
        results << EntityResult.new(entity_type: :skill, name: dr.name, action: dr.action, record: dr.record)
      end

      # Tools — agents reference tools by name.
      tools_result = Deployers::ToolsDeployer.call(
        document:    document,
        resolutions: @resolutions
      )
      raise deploy_error("tools", tools_result) unless tools_result.success?

      tools_result.payload[:tools].each do |dr|
        results << EntityResult.new(entity_type: :tool, name: dr.name, action: dr.action, record: dr.record)
      end

      # Agents last — references skills, tools, and team.
      agents_result = Deployers::AgentsDeployer.call(
        document:    document,
        team:        team_record,
        resolutions: @resolutions
      )
      raise deploy_error("agents", agents_result) unless agents_result.success?

      agents_result.payload[:agents].each do |dr|
        results << EntityResult.new(entity_type: :agent, name: dr.name, action: dr.action, record: dr.record)
      end

      results
    end

    # Deploy workspace files to disk (outside the AR transaction).
    def deploy_workspace_files(document)
      return [] if document.workspace_files.empty?

      result = Deployers::WorkspaceFilesDeployer.call(document: document)
      return result.payload[:workspace_files] if result.success?

      Rails.logger.warn("[SwarmImporter] WorkspaceFilesDeployer failed: #{result.message}")
      []
    end

    # Deploy scheduled tasks (inside or outside transaction — uses AR).
    # Called after deploy_all so agent records already exist.
    def deploy_scheduled_tasks(document)
      return [] if document.scheduled_tasks.empty?

      result = Deployers::ScheduledTasksDeployer.call(
        document:    document,
        resolutions: @resolutions
      )
      return result.payload[:scheduled_tasks] if result.success?

      Rails.logger.warn("[SwarmImporter] ScheduledTasksDeployer failed: #{result.message}")
      []
    end

    # Deploy heartbeat config (Settings update).
    def deploy_heartbeat_config(document)
      result = Deployers::HeartbeatConfigDeployer.call(document: document)
      return result.payload[:heartbeat_config] if result.success?

      Rails.logger.warn("[SwarmImporter] HeartbeatConfigDeployer failed: #{result.message}")
      HeartbeatConfigResult.new(action: :skipped)
    end

    # Convert ScheduledTask DeployResults into EntityResults for the report.
    def scheduled_task_results_as_entity_results(task_results)
      task_results.map do |dr|
        EntityResult.new(
          entity_type: :scheduled_task,
          name:        dr.name,
          action:      dr.action,
          record:      dr.respond_to?(:record) ? dr.record : nil
        )
      end
    end

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    # Raise a RuntimeError with a descriptive message. The outer rescue catches
    # RuntimeError specifically so unrelated errors (bugs in pre-deploy stages)
    # are not silently swallowed under a :deploy stage label.
    def deploy_error(stage_name, service_result)
      RuntimeError.new("Deploy failed at #{stage_name}: #{service_result.message}")
    end

    # Build informational warnings from detected conflicts, noting which resolution
    # strategy will be applied (or defaulting to :skip).
    def build_conflict_warnings(conflict_report)
      return [] if conflict_report.none?

      conflict_report.conflicts.map do |conflict|
        strategy = @resolutions[conflict.name]&.to_sym || :skip
        "Conflict: #{conflict.entity_type} '#{conflict.name}' already exists — #{strategy}"
      end
    end

    # Rebuild a SwarmDocument from a resolved-variable manifest Hash.
    # Only rebuildable fields (strings that may contain {{VAR}}) are updated;
    # structural fields like variables{} are carried over from the original.
    def rebuild_document(original, manifest)
      m = manifest.with_indifferent_access

      SwarmDocument.new(
        swarm_version:    m[:swarm_version] || original.swarm_version,
        name:             m[:name]          || original.name,
        slug:             m[:slug].presence || original.slug,
        description:      m[:description].presence || original.description,
        author:           SwarmDocument::SwarmAuthor.from_hash(m[:author]),
        version:          m[:version].presence    || original.version,
        license:          m[:license].presence    || original.license,
        tags:             Array(m[:tags]),
        icon:             m[:icon].presence       || original.icon,
        homepage:         m[:homepage].presence   || original.homepage,
        requires:         SwarmDocument::SwarmRequirements.from_hash(m[:requires]),
        team:             SwarmDocument::SwarmTeam.from_hash(m[:team]),
        agents:           Array(m[:agents]),
        skills:           Array(m[:skills]),
        tools:            Array(m[:tools]),
        channels:         Array(m[:channels]),
        mcp_servers:      Array(m[:mcp_servers]),
        api_integrations: Array(m[:api_integrations]),
        variables:        original.variables,
        workspace_files:  Array(m[:workspace_files]),
        scheduled_tasks:  Array(m[:scheduled_tasks]),
        heartbeat_config: m[:heartbeat_config].presence || original.heartbeat_config
      )
    end
  end
end
