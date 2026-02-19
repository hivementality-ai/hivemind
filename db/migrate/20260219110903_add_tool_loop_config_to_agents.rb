# frozen_string_literal: true

class AddToolLoopConfigToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :tool_loop_config, :jsonb, default: {}, null: false
  end
end