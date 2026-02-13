# frozen_string_literal: true

class AddPhase2ColumnsToAgents < ActiveRecord::Migration[8.0]
  def change
    add_column :agents, :current_task, :text
    add_column :agents, :model_provider, :string, default: "openai"
    add_column :agents, :model_name, :string, default: "gpt-4"
    add_column :agents, :enabled, :boolean, default: true, null: false
    add_column :agents, :daily_budget_limit, :decimal, precision: 10, scale: 4, default: 10.0
    add_column :agents, :monthly_budget_limit, :decimal, precision: 10, scale: 4, default: 100.0

    add_index :agents, :enabled
  end
end
