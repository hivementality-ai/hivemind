# frozen_string_literal: true

class UsageRecord < ApplicationRecord
  belongs_to :agent
  belongs_to :session, optional: true

  validates :provider, presence: true

  scope :recent, -> { where("created_at > ?", 24.hours.ago) }
  scope :for_period, ->(start_at, end_at) { where(created_at: start_at..end_at) }

  after_initialize :set_defaults

  def total_tokens
    (input_tokens || 0) + (output_tokens || 0)
  end

  private

  def set_defaults
    self.input_tokens ||= 0
    self.output_tokens ||= 0
    self.cache_tokens ||= 0
    self.cost_cents ||= 0
    self.metadata ||= {}
  end
end
