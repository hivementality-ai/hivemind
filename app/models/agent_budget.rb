# frozen_string_literal: true

# AgentBudget - Cost tracking and limits per agent
class AgentBudget < ApplicationRecord
  belongs_to :agent

  PERIOD_TYPES = %w[daily weekly monthly].freeze

  validates :period, presence: true
  validates :limit_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :spent_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Alias for compatibility with services
  alias_attribute :period_type, :period

  def remaining_cents
    return 0 unless limit_cents
    limit_cents - (spent_cents || 0)
  end

  def percentage_used
    return 0 if limit_cents.nil? || limit_cents.zero?
    (((spent_cents || 0).to_f / limit_cents) * 100).round(1)
  end

  def exceeded?
    return false unless limit_cents
    (spent_cents || 0) >= limit_cents
  end

  def warning_threshold?
    percentage_used >= 80
  end

  # Returns true if we've already fired an alert at or above +threshold+
  def alerted_at?(threshold)
    last_alerted_threshold.to_i >= threshold
  end

  def reset!
    update!(
      spent_cents: 0,
      last_alerted_threshold: nil,
      reset_at: Time.current
    )
  end
end
