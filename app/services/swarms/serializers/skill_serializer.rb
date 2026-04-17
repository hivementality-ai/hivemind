# frozen_string_literal: true

module Swarms
  module Serializers
    # Converts a Skill record into a swarm skills[] entry hash.
    #
    # Skills are always embedded inline (full content) in the swarm format —
    # there are no external references for skill content.
    #
    # Usage:
    #   hash = SkillSerializer.call(skill: skill_record)
    #   # => { "name" => "...", "summary" => "...", "content" => "...", ... }
    class SkillSerializer
      def self.call(skill:)
        new(skill).call
      end

      def initialize(skill)
        @skill = skill
      end

      def call
        hash = { "name" => @skill.name }

        hash["summary"]     = @skill.summary     if @skill.summary.present?
        hash["description"] = @skill.description if @skill.description.present?
        hash["content"]     = @skill.content      if @skill.content.present?
        hash["category"]    = @skill.category     if @skill.category.present?

        hash
      end
    end
  end
end
