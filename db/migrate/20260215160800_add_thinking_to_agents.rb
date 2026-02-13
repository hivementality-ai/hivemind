# frozen_string_literal: true

class AddThinkingToAgents < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :thinking_enabled, :boolean, default: false, null: false
    add_column :agents, :thinking_budget_tokens, :integer, default: 10000
    add_column :agents, :thinking_visibility, :string, default: "hidden"
  end
end
