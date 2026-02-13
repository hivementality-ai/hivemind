# frozen_string_literal: true

class EnhanceTeamChatSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :team_chat_sessions, :session_key, :string
    add_index :team_chat_sessions, :session_key, unique: true

    # Link agent sessions to team chat sessions so each agent keeps its own context
    add_reference :sessions, :team_chat_session, foreign_key: true, null: true
  end
end
