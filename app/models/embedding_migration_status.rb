# frozen_string_literal: true

class EmbeddingMigrationStatus < ApplicationRecord
  PHASES = %w[shadow ready_for_validation validated complete rolled_back cancelled].freeze

  validates :from_provider, presence: true
  validates :to_provider, presence: true
  validates :phase, inclusion: { in: PHASES }

  scope :active, -> { where(phase: %w[shadow ready_for_validation validated]) }

  def active?
    phase.in?(%w[shadow ready_for_validation validated])
  end

  def complete?
    phase == "complete"
  end

  def rolled_back?
    phase == "rolled_back"
  end
end
