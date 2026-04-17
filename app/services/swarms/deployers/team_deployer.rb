# frozen_string_literal: true

module Swarms
  module Deployers
    # Creates or updates a Team from a SwarmDocument's team{} section.
    #
    # Resolution strategies (passed per-entity via the `resolutions` hash):
    #   :skip      – return the existing team record unchanged
    #   :overwrite – update the existing record with swarm values
    #   :rename    – create a new team with an auto-suffixed name
    #   (none)     – create a new team (no conflict expected)
    #
    # Usage:
    #   result = TeamDeployer.call(document: swarm_doc, resolutions: {})
    #   result.success?        # => true / false
    #   result.payload[:team]  # => Team record (or nil when skipped / no team block)
    class TeamDeployer
      def self.call(document:, resolutions: {})
        new(document, resolutions).call
      end

      def initialize(document, resolutions)
        @document    = document
        @resolutions = resolutions.with_indifferent_access
      end

      def call
        team_data = @document.team
        return ServiceResponse.success(payload: { team: nil }) if team_data.nil?
        return ServiceResponse.success(payload: { team: nil }) if team_data.name.blank?

        strategy = @resolutions[:team]&.to_sym
        existing = Team.find_by(name: team_data.name)

        if existing.nil?
          create_team(team_data)
        else
          apply_strategy(strategy, existing, team_data)
        end
      rescue ActiveRecord::RecordInvalid => e
        ServiceResponse.error(message: "Failed to deploy team: #{e.record.errors.full_messages.join(', ')}")
      rescue StandardError => e
        ServiceResponse.error(message: "Failed to deploy team: #{e.message}")
      end

      private

      def create_team(team_data)
        team = Team.create!(
          name:        team_data.name,
          description: team_data.description,
          custom_soul: team_data.custom_soul
        )
        ServiceResponse.success(payload: { team: team })
      end

      def apply_strategy(strategy, existing, team_data)
        case strategy
        when :skip
          ServiceResponse.success(payload: { team: existing })
        when :overwrite
          existing.update!(
            description: team_data.description,
            custom_soul: team_data.custom_soul
          )
          ServiceResponse.success(payload: { team: existing })
        when :rename
          new_name = unique_name(team_data.name)
          team = Team.create!(
            name:        new_name,
            description: team_data.description,
            custom_soul: team_data.custom_soul
          )
          ServiceResponse.success(payload: { team: team })
        else
          # No resolution strategy but a conflict exists — treat as skip to be safe.
          ServiceResponse.success(payload: { team: existing })
        end
      end

      # Appends an incrementing suffix until the name is unique.
      def unique_name(base)
        candidate = "#{base}-2"
        counter   = 2

        while Team.exists?(name: candidate)
          counter  += 1
          candidate = "#{base}-#{counter}"
        end

        candidate
      end
    end
  end
end
