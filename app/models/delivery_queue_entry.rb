# frozen_string_literal: true

class DeliveryQueueEntry < ApplicationRecord
  belongs_to :channel
  belongs_to :agent, optional: true
  belongs_to :session, optional: true

  validates :recipient, presence: true
  validates :content, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending sent failed dead_letter] }
  validates :attempts, numericality: { greater_than_or_equal_to: 0 }
  validates :max_attempts, numericality: { greater_than: 0 }

  scope :pending, -> { where(status: "pending") }
  scope :failed, -> { where(status: "failed") }
  scope :dead_letter, -> { where(status: "dead_letter") }
  scope :due_for_retry, -> { pending.where("next_attempt_at <= ?", Time.current) }
end
