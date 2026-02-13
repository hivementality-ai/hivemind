# frozen_string_literal: true

class AgentBudget < ApplicationRecord
  belongs_to :agent

  validates :period, presence: true, inclusion: { in: %w[daily weekly monthly] }
  validates :limit_cents, presence: true, numericality: { greater_than: 0 }

  scope :active, -> { where("reset_at > ?", Time.current) }

  after_initialize :set_defaults

  def remaining_cents
    (limit_cents || 0) - (spent_cents || 0)
  end

  def exceeded?
    remaining_cents <= 0
  end

  def warning_threshold?
    return false if limit_cents.nil? || limit_cents.zero?

    (spent_cents || 0) >= (limit_cents * 0.8)
  end

  def usage_percentage
    return 0 if limit_cents.nil? || limit_cents.zero?

    ((spent_cents || 0) / limit_cents * 100).round(1)
  end

  private

  def set_defaults
    self.spent_cents ||= 0
  end
end
