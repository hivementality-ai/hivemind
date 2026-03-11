# frozen_string_literal: true

class CreateAgentMcpServers < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_mcp_servers do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :mcp_server, null: false, foreign_key: true
      t.timestamps
    end

    add_index :agent_mcp_servers, [ :agent_id, :mcp_server_id ], unique: true
  end
end
