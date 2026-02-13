# frozen_string_literal: true

class CreateSubAgentTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :sub_agent_tasks do |t|
      t.references :parent_agent, null: false, foreign_key: { to_table: :agents }
      t.references :child_agent, null: false, foreign_key: { to_table: :agents }
      t.references :parent_session, null: true, foreign_key: { to_table: :sessions }
      t.references :child_session, null: true, foreign_key: { to_table: :sessions }
      t.text :task, null: false
      t.text :result
      t.string :status, default: "pending", null: false # pending, running, completed, failed
      t.string :task_key, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :sub_agent_tasks, :task_key, unique: true
    add_index :sub_agent_tasks, :status
  end
end
