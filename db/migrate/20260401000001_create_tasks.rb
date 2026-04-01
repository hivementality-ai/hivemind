# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks do |t|
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 1
      t.references :agent, foreign_key: true          # assigned agent (nullable)
      t.references :team, null: false, foreign_key: true
      t.references :session, foreign_key: true         # linked conversation (nullable)
      t.string :created_by                              # "user", "agent:<slug>", "hashtag"
      t.datetime :due_date
      t.datetime :completed_at
      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :priority
    add_index :tasks, [ :team_id, :status ]
    add_index :tasks, [ :agent_id, :status ]
  end
end
