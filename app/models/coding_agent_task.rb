# frozen_string_literal: true

class CodingAgentTask < ApplicationRecord
  belongs_to :agent
  belongs_to :session

  validates :task, presence: true
  validates :task_key, presence: true, uniqueness: true
  validates :cli, presence: true, inclusion: { in: %w[claude codex aider] }
  validates :status, inclusion: { in: %w[pending running completed failed] }
  validates :timeout, presence: true, numericality: { in: 1..1800 }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent, -> { order(created_at: :desc).limit(20) }
  scope :for_agent, ->(agent) { where(agent: agent) }

  def duration_seconds
    return nil unless started_at
    ((completed_at || Time.current) - started_at).round(1)
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def active?
    %w[pending running].include?(status)
  end
end
