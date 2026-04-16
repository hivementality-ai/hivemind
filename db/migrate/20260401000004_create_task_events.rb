# frozen_string_literal: true

class CreateTaskEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :task_events do |t|
      t.references :task, null: false, foreign_key: true
      t.references :agent, foreign_key: true, null: true
      t.string :event_type, null: false
      t.text :summary, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :task_events, [ :task_id, :created_at ]
  end
end
