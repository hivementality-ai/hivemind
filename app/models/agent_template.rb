# frozen_string_literal: true

# AgentTemplate - Pre-built agent configurations
class AgentTemplate < ApplicationRecord
  CATEGORIES = %w[
    coding research devops writing data security project creative
    general productivity lifestyle marketing sales design testing
    gamedev support specialized
  ].freeze

  validates :name, presence: true
  validates :role, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :version, presence: true

  scope :featured, -> { where(featured: true) }
  scope :by_category, ->(category) { where(category: category) if category.present? }

  # Groups templates by category, in CATEGORIES order, each group sorted by name.
  # Categories without templates are omitted.
  #
  # @param templates [Enumerable<AgentTemplate>]
  # @return [Hash{String => Array<AgentTemplate>}]
  def self.grouped_by_category(templates)
    by_category = templates.sort_by { |t| t.name.to_s.downcase }.group_by(&:category)
    ordered = CATEGORIES + (by_category.keys - CATEGORIES)
    ordered.each_with_object({}) do |category, groups|
      groups[category] = by_category[category] if by_category.key?(category)
    end
  end

  def enabled_skill_names
    skills_config.dig("enabled") || []
  end

  def enabled_tool_names
    tools_config.dig("enabled") || []
  end

  def deploy(name: nil, team: nil)
    Agents::CreateFromTemplate.call(
      template: self,
      name: name,
      team: team
    )
  end
end
