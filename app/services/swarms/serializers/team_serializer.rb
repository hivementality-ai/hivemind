# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts a Team record into the swarm team{} section hash.
    #
    # The team block is optional in the schema — return nil if there is nothing
    # meaningful to emit (no name). Callers should omit the key entirely when
    # the return value is nil.
    #
    # Usage:
    #   hash = TeamSerializer.call(team: team_record)
    #   # => { "name" => "...", "description" => "...", "custom_soul" => "..." }
    #   # or nil when the team record is nil / has no name
    class TeamSerializer
      def self.call(team:)
        new(team).call
      end

      def initialize(team)
        @team = team
      end

      def call
        return nil if @team.nil?
        return nil if @team.name.blank?

        hash = { "name" => @team.name }
        hash["description"] = @team.description if @team.description.present?
        hash["custom_soul"] = @team.custom_soul  if @team.custom_soul.present?
        hash
      end
    end
  end
end
