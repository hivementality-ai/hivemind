# frozen_string_literal: true

class CreateProjectMilestones < ActiveRecord::Migration[8.1]
  def change
    create_table :project_milestones do |t|
      t.references :project, null: false, foreign_key: true
      t.references :agent, foreign_key: true
      t.references :session, foreign_key: true
      t.string     :title, null: false
      t.text       :description
      t.text       :acceptance_criteria
      t.string     :status, null: false, default: "pending"
      t.integer    :position, null: false, default: 0
      t.jsonb      :depends_on, null: false, default: []
      t.boolean    :requires_approval, null: false, default: true
      t.jsonb      :deliverables, null: false, default: []
      t.text       :agent_notes
      t.text       :review_notes
      t.jsonb      :checkpoint, null: false, default: {}
      t.integer    :retry_count, null: false, default: 0
      t.integer    :max_retries, null: false, default: 3
      t.datetime   :started_at
      t.datetime   :completed_at
      t.datetime   :reviewed_at
      t.datetime   :last_ping_at
      t.integer    :ping_count, null: false, default: 0
      t.jsonb      :metadata, null: false, default: {}
      t.timestamps

      t.index [ :project_id, :position ]
      t.index [ :project_id, :status ]
      t.index [ :status ]
    end
  end
end
