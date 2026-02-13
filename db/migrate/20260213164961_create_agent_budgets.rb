class CreateAgentBudgets < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_budgets do |t|
      t.references :agent, null: false, foreign_key: true
      t.string :period
      t.decimal :limit_cents
      t.decimal :spent_cents
      t.datetime :reset_at

      t.timestamps
    end
  end
end
