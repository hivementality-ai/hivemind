# frozen_string_literal: true

class SubAgentTask < ApplicationRecord
  belongs_to :parent_agent, class_name: "Agent"
  belongs_to :child_agent, class_name: "Agent"
  belongs_to :parent_session, class_name: "Session", optional: true
  belongs_to :child_session, class_name: "Session", optional: true

  validates :task, presence: true
  validates :task_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :active, -> { where(status: %w[pending running]) }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  def duration_seconds
    return nil unless started_at
    ((completed_at || Time.current) - started_at).round(1)
  end
end
