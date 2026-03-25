# frozen_string_literal: true

class CreateProjectEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :project_events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :project_milestone, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :user, foreign_key: true
      t.string     :event_type, null: false
      t.text       :summary, null: false
      t.jsonb      :metadata, null: false, default: {}
      t.datetime   :created_at, null: false
    end

    add_index :project_events, [ :project_id, :created_at ]
    add_index :project_events, :event_type
  end
end
