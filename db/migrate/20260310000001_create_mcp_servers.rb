# frozen_string_literal: true

class CreateMcpServers < ActiveRecord::Migration[8.0]
  def change
    create_table :mcp_servers do |t|
      t.string :name, null: false
      t.string :transport, null: false, default: "stdio"
      t.string :command
      t.string :url
      t.string :npm_package
      t.jsonb :env_vars, default: {}
      t.jsonb :auth_config, default: {}
      t.jsonb :discovered_tools, default: []
      t.boolean :enabled, default: true, null: false
      t.string :status, default: "disconnected", null: false
      t.boolean :preset, default: false, null: false
      t.string :icon
      t.text :last_error
      t.datetime :last_connected_at
      t.datetime :tools_refreshed_at
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :mcp_servers, :name, unique: true
    add_index :mcp_servers, :enabled
    add_index :mcp_servers, :transport
  end
end
