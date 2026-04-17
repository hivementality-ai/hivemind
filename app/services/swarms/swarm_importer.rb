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
      # document                  – SwarmDocument that was imported
      # entity_results            – Array<EntityResult> in deploy order
      # warnings                  – Array<String> informational messages
      # variable_overrides_applied – Hash of variable values that were substituted
      # vault_refs_checked        – Array<String> vault paths that were verified

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

      resolved_manifest         = resolver_result.payload[:manifest]
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

      # Stage 6: build and return the import report
      report = ImportReport.new(
        document:                   document,
        entity_results:             entity_results,
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
    rescue StandardError => e
      ServiceResponse.error(
        message: "Import failed: #{e.message}",
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

      team_record = team_result.payload[:team]
      results << EntityResult.new(
        entity_type: :team,
        name:        document.team&.name,
        action:      team_action(team_record, document.team),
        record:      team_record
      ) if document.team&.name.present?

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

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------

    # Raise a RuntimeError that will be caught by the outer rescue and will roll
    # back the transaction before being re-surfaced as a ServiceResponse.error.
    def deploy_error(stage_name, service_result)
      RuntimeError.new("Deploy failed at #{stage_name}: #{service_result.message}")
    end

    # Determine the team deploy action. TeamDeployer doesn't return a DeployResult
    # value object — it just returns the record. We infer the action from context.
    def team_action(team_record, team_data)
      return :skipped if team_record.nil?
      return :created if team_record.created_at == team_record.updated_at

      team_record.name == team_data&.name ? :updated : :created
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
        variables:        original.variables
      )
    end
  end
end
