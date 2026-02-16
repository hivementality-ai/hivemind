class AddIndexes < ActiveRecord::Migration[8.1]
  def change
    # Sessions
    add_index :sessions, :session_key, unique: true
    add_index :sessions, [ :agent_id, :status ]
    add_index :sessions, :last_activity_at

    # Vault entries
    add_index :vault_entries, [ :agent_id, :namespace, :key ], unique: true, name: "idx_vault_unique_entry"

    # Audit logs
    add_index :audit_logs, [ :actor_type, :actor_id ]
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at

    # API tokens
    add_index :api_tokens, :token_digest, unique: true

    # Agents
    add_index :agents, :name, unique: true
    add_index :agents, :status

    # Teams
    add_index :teams, :name, unique: true

    # Channels
    add_index :channels, :channel_type

    # Team messages
    add_index :team_messages, [ :team_id, :created_at ]

    # Scheduled tasks
    add_index :scheduled_tasks, [ :agent_id, :enabled ]

    # Device pairings
    add_index :device_pairings, :device_id, unique: true
    add_index :device_pairings, :status
  end
end
