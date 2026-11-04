# frozen_string_literal: true

class CreateAgentConnectorExclusions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_connector_exclusions do |t|
      t.references :agent, null: false, foreign_key: true
      t.references :connector, null: false, foreign_key: true
      t.timestamps
    end

    add_index :agent_connector_exclusions, [ :agent_id, :connector_id ], unique: true
  end
end
