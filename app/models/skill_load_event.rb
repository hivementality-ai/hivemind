# frozen_string_literal: true

# Records every skill load for analytics — which skills get loaded,
# by which agents, in which tier, at what relevance score.
class SkillLoadEvent < ApplicationRecord
  belongs_to :skill
  belongs_to :agent
  belongs_to :session, optional: true

  validates :load_tier, inclusion: { in: %w[core contextual manual] }

  scope :for_agent, ->(agent) { where(agent: agent) }
  scope :for_skill, ->(skill) { where(skill: skill) }
  scope :by_tier, ->(tier) { where(load_tier: tier) }
  scope :core, -> { by_tier("core") }
  scope :contextual, -> { by_tier("contextual") }
  scope :manual, -> { by_tier("manual") }
  scope :recent, -> { order(created_at: :desc) }

  # Aggregated stats for a skill.
  def self.stats_for(skill)
    events = for_skill(skill)
    {
      total_loads: events.count,
      core_loads: events.core.count,
      contextual_loads: events.contextual.count,
      manual_loads: events.manual.count,
      avg_relevance_score: events.contextual.average(:relevance_score)&.round(3),
      helpful_count: events.where(was_helpful: true).count,
      not_helpful_count: events.where(was_helpful: false).count
    }
  end

  # Aggregated stats for an agent.
  def self.stats_for_agent(agent)
    events = for_agent(agent)
    by_skill = events.group(:skill_id).count

    {
      total_loads: events.count,
      unique_skills_loaded: by_skill.keys.size,
      most_loaded_skill_id: by_skill.max_by { |_, v| v }&.first,
      loads_by_tier: events.group(:load_tier).count
    }
  end
end
