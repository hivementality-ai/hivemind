# frozen_string_literal: true

class AddLastAlertedThresholdToAgentBudgets < ActiveRecord::Migration[7.2]
  def change
    add_column :agent_budgets, :last_alerted_threshold, :integer
  end
end
