# frozen_string_literal: true

class AddAssociationsToTasks < ActiveRecord::Migration[8.0]
  def change
    add_reference :tasks, :project,           foreign_key: true,                              null: true
    add_reference :tasks, :project_milestone, foreign_key: { to_table: :project_milestones }, null: true
    add_reference :tasks, :session,           foreign_key: true,                              null: true
  end
end
