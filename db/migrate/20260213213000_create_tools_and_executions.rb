# frozen_string_literal: true

class CreateToolsAndExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :tools do |t|
      t.string :name, null: false
      t.string :description, null: false
      t.string :executor_type, null: false # shell, file_read, file_write, web_search, web_fetch, http_request
      t.jsonb :parameters_schema, null: false, default: {} # JSON Schema for tool params
      t.jsonb :config, null: false, default: {}             # executor-specific config
      t.boolean :requires_approval, null: false, default: false
      t.boolean :enabled, null: false, default: true
      t.boolean :builtin, null: false, default: false
      t.timestamps
    end

    add_index :tools, :name, unique: true
    add_index :tools, :enabled

    create_table :tool_executions do |t|
      t.references :tool, null: false, foreign_key: true
      t.references :agent, null: false, foreign_key: true
      t.references :session, null: false, foreign_key: true
      t.string :status, null: false, default: "pending" # pending, approved, running, completed, failed, denied
      t.jsonb :input, null: false, default: {}
      t.text :output
      t.text :error
      t.integer :duration_ms
      t.integer :exit_code
      t.timestamps
    end

    add_index :tool_executions, :status

    # Join table: which agents can use which tools
    create_table :agent_tools do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :tool, null: false, foreign_key: true
      t.timestamps
    end

    add_index :agent_tools, [:agent_id, :tool_id], unique: true
  end
end
