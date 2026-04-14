# frozen_string_literal: true

class TaskTemplate < ApplicationRecord
  has_many :task_hooks, dependent: :destroy
  has_many :tasks, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :default_priority, inclusion: { in: Task::PRIORITIES }
end
