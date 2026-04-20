# frozen_string_literal: true

class AddTransitionLockedAtToTasks < ActiveRecord::Migration[7.2]
  def change
    add_column :tasks, :transition_locked_at, :datetime, null: true
    add_column :tasks, :transition_locked_by_agent_id, :bigint, null: true

    add_index :tasks, :transition_locked_at
    add_foreign_key :tasks, :agents, column: :transition_locked_by_agent_id
  end
end
