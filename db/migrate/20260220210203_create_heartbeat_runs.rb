# frozen_string_literal: true

class CreateHeartbeatRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :heartbeat_runs do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :session, foreign_key: true
      t.string :status, null: false, default: "ok"        # ok, action_taken, error, skipped
      t.text :summary                                       # agent reply or error message
      t.integer :input_tokens, default: 0
      t.integer :output_tokens, default: 0
      t.integer :duration_ms                                # how long the run took
      t.string :model                                       # model used for this run
      t.jsonb :metadata, default: {}                        # extra context (tasks checked, delegations made, etc.)
      t.timestamps
    end

    add_index :heartbeat_runs, :status
    add_index :heartbeat_runs, :created_at
  end
end
