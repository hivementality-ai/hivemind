# frozen_string_literal: true

class TaskHook < ApplicationRecord
  TRIGGERS = %w[pre post].freeze

  belongs_to :task, optional: true
  belongs_to :task_template, optional: true
  belongs_to :skill

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :on_status, inclusion: { in: Task::STATUSES }
  validates :skill_id, presence: true
  validate :task_or_template_present

  scope :enabled, -> { where(enabled: true) }
  scope :pre_hooks, -> { where(trigger: "pre") }
  scope :post_hooks, -> { where(trigger: "post") }
  scope :for_status, ->(s) { where(on_status: s) }
  scope :ordered, -> { order(:position) }

  private

  def task_or_template_present
    if task_id.blank? && task_template_id.blank?
      errors.add(:base, "must belong to a task or a task template")
    end
    if task_id.present? && task_template_id.present?
      errors.add(:base, "cannot belong to both a task and a task template")
    end
  end
end
