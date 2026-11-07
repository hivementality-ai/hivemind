# frozen_string_literal: true

# Per-agent "ask me first" switches, and whether a scheduled task may send without a card.
class AddApprovalCardSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :agents, :ask_first_overrides, :jsonb, default: {}, null: false
    add_column :scheduled_tasks, :allow_sending, :boolean, default: false, null: false
  end
end
