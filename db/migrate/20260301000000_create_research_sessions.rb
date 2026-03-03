# frozen_string_literal: true

class CreateResearchSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :research_sessions do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :session, null: false, foreign_key: true
      t.string :query, null: false
      t.string :status, null: false, default: "queued"
      t.string :depth, null: false, default: "standard"
      t.string :focus, null: false, default: "general"
      t.string :output_format, null: false, default: "report"
      t.string :current_phase
      t.integer :sources_count, null: false, default: 0
      t.jsonb :sources, default: []
      t.jsonb :findings, default: []
      t.jsonb :progress_log, default: []
      t.text :report
      t.text :error_message
      t.string :task_key, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :research_sessions, :status
    add_index :research_sessions, [ :agent_id, :created_at ]
    add_index :research_sessions, :task_key, unique: true
  end
end
