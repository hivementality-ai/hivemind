# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks do |t|
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "backlog"
      t.string :priority, null: false, default: "medium"
      t.references :created_by_agent, foreign_key: { to_table: :agents }
      t.references :assigned_to_agent, foreign_key: { to_table: :agents }
      t.jsonb :comments, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.datetime :due_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :priority
    add_index :tasks, [ :assigned_to_agent_id, :status ]
    add_index :tasks, :created_at
  end
end
