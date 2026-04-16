# frozen_string_literal: true

class TaskHook < ApplicationRecord
  TRIGGERS = %w[pre post].freeze

  belongs_to :task, optional: true
  belongs_to :task_template, optional: true
  belongs_to :team, optional: true
  belongs_to :skill, optional: true
  belongs_to :agent, optional: true

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :on_status, inclusion: { in: Task::STATUSES }
  validate :exactly_one_owner

  scope :enabled, -> { where(enabled: true) }
  scope :pre_hooks, -> { where(trigger: "pre") }
  scope :post_hooks, -> { where(trigger: "post") }
  scope :for_status, ->(s) { where(on_status: s) }
  scope :ordered, -> { order(:position) }

  # Human-readable label for the hook's scope
  def scope_label
    if task_id.present?
      "Task ##{task_id}"
    elsif task_template_id.present?
      "Template: #{task_template&.name}"
    elsif team_id.present?
      "Team default"
    else
      "Unknown"
    end
  end

  # Human-readable label for the assigned agent
  def agent_label
    agent&.name || "No auto-assign"
  end

  private

  def exactly_one_owner
    owners = [ task_id, task_template_id, team_id ].compact
    if owners.empty?
      errors.add(:base, "must belong to a task, task template, or team")
    elsif owners.size > 1
      errors.add(:base, "can only belong to one of: task, task template, or team")
    end
  end
end
