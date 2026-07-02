# frozen_string_literal: true

class HeartbeatRun < ApplicationRecord
  belongs_to :agent
  belongs_to :session, optional: true

  validates :status, presence: true, inclusion: { in: %w[ok action_taken error skipped] }

  after_create :emit_completed_webhook

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

  private

  def emit_completed_webhook
    WebhookEmitter.emit(
      "heartbeat.completed",
      { heartbeat_run_id: id, agent_id: agent_id, status: status, duration_ms: duration_ms, completed_at: created_at.iso8601 },
      agent: agent
    )
  end
end
