# frozen_string_literal: true

class AddTaskTemplateToTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :tasks, :task_template, foreign_key: true, null: true
  end
end
