# frozen_string_literal: true

class CreateApprovalRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :approval_requests do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :action, null: false
      t.string :resource, null: false
      t.jsonb :params, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.datetime :requested_at, null: false
      t.datetime :resolved_at
      t.string :resolved_by
      t.datetime :expires_at
      t.text :resolution_notes

      t.timestamps
    end

    add_index :approval_requests, :status
    add_index :approval_requests, [ :agent_id, :status ]
    add_index :approval_requests, :expires_at
  end
end
