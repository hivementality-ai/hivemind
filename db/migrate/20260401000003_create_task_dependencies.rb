# frozen_string_literal: true

class CreateTaskDependencies < ActiveRecord::Migration[8.0]
  def change
    create_table :task_dependencies do |t|
      t.references :task, null: false, foreign_key: true
      t.references :depends_on, null: false, foreign_key: { to_table: :tasks }
      t.timestamps
    end

    add_index :task_dependencies, [ :task_id, :depends_on_id ], unique: true
  end
end
