# frozen_string_literal: true

class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string     :title, null: false
      t.text       :description
      t.string     :status, null: false, default: "planning"
      t.string     :priority, null: false, default: "normal"
      t.datetime   :deadline
      t.jsonb      :notification_prefs, null: false, default: {}
      t.jsonb      :metadata, null: false, default: {}
      t.datetime   :started_at
      t.datetime   :completed_at
      t.timestamps

      t.index [ :team_id, :status ]
      t.index [ :status ]
    end
  end
end
