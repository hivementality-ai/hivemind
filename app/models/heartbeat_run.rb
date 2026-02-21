# frozen_string_literal: true

class HeartbeatRun < ApplicationRecord
  belongs_to :agent
  belongs_to :session, optional: true

  validates :status, presence: true, inclusion: { in: %w[ok action_taken error skipped] }

  scope :recent, -> { order(created_at: :desc).limit(50) }
  scope :errors, -> { where(status: "error") }
  scope :actions, -> { where(status: "action_taken") }
  scope :for_agent, ->(agent) { where(agent: agent) }

  def ok?
    status == "ok"
  end

  def total_tokens
    (input_tokens || 0) + (output_tokens || 0)
  end
end
