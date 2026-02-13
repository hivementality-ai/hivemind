# frozen_string_literal: true

class AddSystemAgentFlag < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :system_agent, :boolean, default: false, null: false
  end
end
