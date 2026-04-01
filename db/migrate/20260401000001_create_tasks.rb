# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks do |t|
      t.string  :title,    null: false
      t.text    :description
      t.integer :status,   null: false, default: 1   # default: todo
      t.integer :priority, null: false, default: 1   # default: medium

      t.references :team,              null: false, foreign_key: true
      t.references :user,              null: false, foreign_key: true
      t.references :agent,             foreign_key: true                   # assignee (nullable)
      t.references :created_by_agent,  foreign_key: { to_table: :agents }  # creator agent (nullable)
      t.references :session,           foreign_key: true                   # linked conversation (nullable)
      t.references :project,           foreign_key: true                   # linked project (nullable)
      t.references :project_milestone, foreign_key: true                   # linked milestone (nullable)

      t.string   :created_by            # "user", "agent:<slug>", "hashtag"
      t.datetime :due_date
      t.datetime :completed_at
      t.integer  :position, null: false, default: 0
      t.jsonb    :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :priority
    add_index :tasks, [ :team_id, :status ]
    add_index :tasks, [ :agent_id, :status ]
    add_index :tasks, :project_id
    add_index :tasks, :project_milestone_id
  end
end
