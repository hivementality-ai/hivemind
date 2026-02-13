# frozen_string_literal: true

class CreateTeamChat < ActiveRecord::Migration[8.0]
  def change
    create_table :team_chat_sessions do |t|
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.integer :status, default: 0, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    create_table :team_chat_messages do |t|
      t.references :team_chat_session, null: false, foreign_key: true
      t.string :sender_type, null: false  # "user" or "agent"
      t.bigint :sender_id, null: false    # user_id or agent_id
      t.bigint :target_agent_id           # nil = broadcast, else specific agent
      t.text :content, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :team_chat_messages, :target_agent_id
    add_index :team_chat_messages, [:sender_type, :sender_id]
  end
end
