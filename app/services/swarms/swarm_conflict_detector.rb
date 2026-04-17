# frozen_string_literal: true

module Swarms
  # Detects name collisions between entities in a SwarmDocument and entities
  # that already exist in the platform database.
  #
  # Each conflict describes a single name collision. The caller (e.g. an import
  # controller or UI layer) decides how to resolve each one using one of the
  # three supported strategies:
  #
  #   :skip      – ignore the incoming entity; keep the existing platform record
  #   :rename    – auto-suffix the incoming entity name (e.g. "my-tool" → "my-tool-2")
  #   :overwrite – replace the existing platform record with the swarm definition
  #
  # Entity types checked:
  #   :team             – Team.name
  #   :agents           – Agent.name
  #   :skills           – Skill.name
  #   :tools            – Tool.name
  #   :channels         – Channel.name
  #   :mcp_servers      – McpServer.name
  #   :api_integrations – ApiIntegration.name
  #
  # Usage:
  #   result = SwarmConflictDetector.call(document: swarm_doc)
  #   result.success?                         # => always true
  #   report = result.payload                 # => ConflictReport
  #   report.any?                             # => true / false
  #   report.conflicts                        # => [Conflict, ...]
  #   report.conflicts_for(:skills)           # => [Conflict, ...]
  #   report.by_type                          # => { skills: [Conflict, ...], ... }
  #
  # A ConflictReport is always returned — even when there are zero conflicts —
  # so callers always receive a uniform interface regardless of import contents.
  class SwarmConflictDetector
    # -------------------------------------------------------------------------
    # Value objects
    # -------------------------------------------------------------------------

    # A single collision between a swarm entity and an existing platform record.
    #
    # entity_type  – Symbol, one of ENTITY_TYPES
    # name         – String, the colliding name
    # swarm_index  – Integer, position in the swarm document's array (0 for :team)
    Conflict = Data.define(:entity_type, :name, :swarm_index) do
      # All supported resolution strategies for any conflict.
      def resolution_strategies
        %i[skip rename overwrite]
      end
    end

    # Aggregate result returned in ServiceResponse#payload.
    ConflictReport = Data.define(:conflicts) do
      def any?  = conflicts.any?
      def none? = conflicts.empty?
      def count = conflicts.size

      # Conflicts belonging to a single entity type.
      def conflicts_for(entity_type)
        conflicts.select { |c| c.entity_type == entity_type.to_sym }
      end

      # All conflicts grouped by entity_type for easy iteration.
      def by_type
        conflicts.group_by(&:entity_type)
      end
    end

    # -------------------------------------------------------------------------
    # Constants
    # -------------------------------------------------------------------------

    # Ordered list of entity types the detector inspects.
    ENTITY_TYPES = %i[team agents skills tools channels mcp_servers api_integrations].freeze

    # Maps entity_type symbol → [AR model class, name column symbol].
    # :team is handled separately (single record, not an array).
    ARRAY_ENTITY_MAP = {
      agents:           [Agent,          :name],
      skills:           [Skill,          :name],
      tools:            [Tool,           :name],
      channels:         [Channel,        :name],
      mcp_servers:      [McpServer,      :name],
      api_integrations: [ApiIntegration, :name]
    }.freeze

    # -------------------------------------------------------------------------
    # Entry point
    # -------------------------------------------------------------------------

    def self.call(document:)
      new(document).call
    end

    def initialize(document)
      @document = document
    end

    def call
      conflicts = []

      conflicts.concat(detect_team_conflict)

      ARRAY_ENTITY_MAP.each do |entity_type, (model_class, name_col)|
        swarm_entities = @document.public_send(entity_type)
        conflicts.concat(detect_array_conflicts(entity_type, swarm_entities, model_class, name_col))
      end

      ServiceResponse.success(payload: ConflictReport.new(conflicts: conflicts.freeze))
    end

    private

    # -------------------------------------------------------------------------
    # Team — at most one team block; no array index beyond 0
    # -------------------------------------------------------------------------

    def detect_team_conflict
      return [] if @document.team.nil?
      return [] if @document.team.name.blank?

      if Team.exists?(name: @document.team.name)
        [Conflict.new(entity_type: :team, name: @document.team.name, swarm_index: 0)]
      else
        []
      end
    end

    # -------------------------------------------------------------------------
    # Array sections (agents, skills, tools, channels, mcp_servers)
    # -------------------------------------------------------------------------

    # Collects all incoming names in a single DB query rather than N lookups,
    # then builds Conflict objects for each name that already exists.
    #
    # SwarmDocument stores entity arrays as plain Hashes (produced by
    # SwarmParser#normalize_array), accessed with indifferent keys.
    def detect_array_conflicts(entity_type, swarm_entities, model_class, name_col)
      return [] if swarm_entities.empty?

      incoming = indexed_names(swarm_entities, name_col)
      return [] if incoming.empty?

      existing = model_class.where(name_col => incoming.values)
                            .pluck(name_col)
                            .to_set

      return [] if existing.empty?

      incoming.filter_map do |index, name|
        next unless existing.include?(name)

        Conflict.new(entity_type: entity_type, name: name, swarm_index: index)
      end
    end

    # Returns a Hash of { array_index => name_string } for all entities that
    # have a non-blank value at name_col.
    def indexed_names(swarm_entities, name_col)
      swarm_entities.each_with_index.each_with_object({}) do |(entity, index), acc|
        h    = entity.is_a?(Hash) ? entity.with_indifferent_access : {}
        name = h[name_col].presence
        acc[index] = name if name
      end
    end
  end
end
