# frozen_string_literal: true

class TaskDependency < ApplicationRecord
  belongs_to :task
  belongs_to :depends_on, class_name: "Task"

  validates :depends_on_id, uniqueness: { scope: :task_id, message: "dependency already exists" }
  validate :no_self_dependency
  validate :no_circular_dependency

  private

  def no_self_dependency
    errors.add(:depends_on_id, "a task cannot depend on itself") if task_id == depends_on_id
  end

  def no_circular_dependency
    return if depends_on_id.blank? || task_id.blank?

    if TaskDependency.exists?(task_id: depends_on_id, depends_on_id: task_id)
      errors.add(:base, "circular dependency: #{depends_on_id} already depends on #{task_id}")
    end
  end
end
