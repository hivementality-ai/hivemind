# frozen_string_literal: true

class Task < ApplicationRecord
  belongs_to :agent, optional: true
  belongs_to :team
  belongs_to :session, optional: true

  enum :status, { backlog: 0, todo: 1, in_progress: 2, review: 3, done: 4 }, default: :todo
  enum :priority, { low: 0, medium: 1, high: 2, urgent: 3 }, default: :medium, prefix: true

  validates :title, presence: true
  validates :status, presence: true
  validates :priority, presence: true

  scope :active, -> { where.not(status: :done) }
  scope :assigned_to, ->(agent) { where(agent: agent) }
  scope :by_status, ->(s) { where(status: s) }
  scope :by_priority, ->(p) { where(priority: p) }
  scope :overdue, -> { where("due_date < ? AND status != ?", Time.current, statuses[:done]) }
  scope :for_team, ->(team) { where(team: team) }

  after_update :set_completed_at, if: -> { saved_change_to_status? && done? }
  after_update :broadcast_update
  after_create :broadcast_create

  private

  def set_completed_at
    update_column(:completed_at, Time.current) if completed_at.nil?
  end

  def broadcast_update
    ActionCable.server.broadcast("tasks_#{team_id}", {
      type: "task_updated",
      task: as_broadcast_json
    })
  end

  def broadcast_create
    ActionCable.server.broadcast("tasks_#{team_id}", {
      type: "task_created",
      task: as_broadcast_json
    })
  end

  def as_broadcast_json
    {
      id: id,
      title: title,
      status: status,
      priority: priority,
      agent_id: agent_id,
      agent_name: agent&.name,
      due_date: due_date&.iso8601,
      created_by: created_by
    }
  end
end
