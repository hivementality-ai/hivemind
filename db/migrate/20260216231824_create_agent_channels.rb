class CreateAgentChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_channels do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :channel, null: false, foreign_key: true
      t.string :vault_token_key       # VaultEntry key for this agent's bot token
      t.string :external_bot_user_id  # Slack bot_user_id for @mention routing
      t.boolean :is_default, default: false  # default responder for this channel
      t.jsonb :config, default: {}    # extra platform config (display name override, etc.)
      t.timestamps
    end

    add_index :agent_channels, [ :agent_id, :channel_id ], unique: true
  end
end
