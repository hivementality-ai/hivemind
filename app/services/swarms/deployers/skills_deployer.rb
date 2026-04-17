# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates Skill records from a SwarmDocument's skills[] section.
    #
    # Each skill entry in the swarm document is a plain Hash (as produced by
    # SwarmParser#normalize_array) with indifferent-access keys.
    #
    # Resolution strategies are keyed by skill name:
    #   :skip      – keep existing skill, return it in the results
    #   :overwrite – update existing skill attributes with swarm values
    #   :rename    – create new skill with an auto-suffixed name
    #   (none)     – create new skill (no conflict expected)
    #
    # The payload always contains a :skills array of DeployResult value objects,
    # one per skill in the document, in document order.
    #
    # Usage:
    #   result = SkillsDeployer.call(document: swarm_doc, resolutions: {})
    #   result.success?         # => true / false
    #   result.payload[:skills] # => [DeployResult, ...]
    class SkillsDeployer
      # Outcome for a single deployed skill.
      DeployResult = Data.define(:name, :record, :action) do
        # action is one of: :created, :updated, :skipped, :renamed
      end

      def self.call(document:, resolutions: {})
        new(document, resolutions).call
      end

      def initialize(document, resolutions)
        @document    = document
        @resolutions = resolutions.with_indifferent_access
      end

      def call
        results = @document.skills.map.with_index do |skill_hash, index|
          deploy_skill(skill_hash.with_indifferent_access, index)
        end

        ServiceResponse.success(payload: { skills: results })
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy skills: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy skills: #{e.message}")
      end

      private

      def deploy_skill(skill_hash, _index)
        name     = skill_hash[:name].to_s
        strategy = @resolutions[name]&.to_sym
        existing = Skill.find_by(name: name)

        if existing.nil?
          record = create_skill(name, skill_hash)
          DeployResult.new(name: name, record: record, action: :created)
        else
          apply_strategy(strategy, existing, name, skill_hash)
        end
      end

      def create_skill(name, skill_hash)
        Skill.create!(build_attributes(name, skill_hash))
      end

      def apply_strategy(strategy, existing, name, skill_hash)
        case strategy
        when :skip
          DeployResult.new(name: name, record: existing, action: :skipped)
        when :overwrite
          existing.update!(build_attributes(name, skill_hash))
          DeployResult.new(name: name, record: existing, action: :updated)
        when :rename
          new_name = unique_name(name)
          record   = create_skill(new_name, skill_hash.merge(name: new_name))
          DeployResult.new(name: new_name, record: record, action: :renamed)
        else
          # No resolution provided but conflict exists — skip to be safe.
          DeployResult.new(name: name, record: existing, action: :skipped)
        end
      end

      def build_attributes(name, skill_hash)
        {
          name:        name,
          summary:     skill_hash[:summary].presence || name.truncate(150),
          description: skill_hash[:description].presence,
          content:     skill_hash[:content].presence || "# Imported from swarm",
          category:    skill_hash[:category].presence,
          enabled:     skill_hash.key?(:enabled) ? skill_hash[:enabled] : true,
          source:      "swarm"
        }
      end

      # Appends an incrementing suffix until the name is unique.
      def unique_name(base)
        candidate = "#{base}-2"
        counter   = 2

        while Skill.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
