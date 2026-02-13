# frozen_string_literal: true

# AgentTemplate - Pre-built agent configurations
class AgentTemplate < ApplicationRecord
  CATEGORIES = %w[coding research devops writing data security project creative general].freeze
  
  validates :name, presence: true
  validates :role, presence: true
  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :version, presence: true
  
  scope :featured, -> { where(featured: true) }
  scope :by_category, ->(category) { where(category: category) if category.present? }
  
  def deploy(name: nil, team: nil)
    Agents::CreateFromTemplate.call(
      template: self,
      name: name,
      team: team
    )
  end
end
