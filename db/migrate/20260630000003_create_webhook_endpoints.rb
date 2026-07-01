# frozen_string_literal: true

class CreateWebhookEndpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.string :url, null: false
      t.text :secret # encrypted via `encrypts :secret` — HMAC signing key
      t.jsonb :event_types, null: false, default: []
      t.boolean :enabled, null: false, default: true

      # Scope: agent-scoped, team-scoped, or global (both nil) — mirrors VaultEntry
      t.references :agent, null: true, foreign_key: true
      t.references :team, null: true, foreign_key: true

      # Delivery bookkeeping
      t.datetime :last_delivered_at
      t.integer :last_status
      t.integer :failure_count, null: false, default: 0

      t.timestamps
    end

    add_index :webhook_endpoints, :event_types, using: :gin
    add_index :webhook_endpoints, :enabled
  end
end
