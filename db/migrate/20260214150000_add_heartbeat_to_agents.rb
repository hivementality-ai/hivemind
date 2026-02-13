# frozen_string_literal: true

class AddHeartbeatToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :heartbeat_enabled, :boolean, default: false, null: false
    add_column :agents, :heartbeat_interval_minutes, :integer, default: 30, null: false
    add_column :agents, :heartbeat_prompt, :text
    add_column :agents, :heartbeat_last_run_at, :datetime
  end
end
