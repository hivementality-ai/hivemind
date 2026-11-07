# frozen_string_literal: true

# Optional watch URL on a scheduled task, what was last seen there, and the outcome of the latest check.
class AddPrecheckToScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :scheduled_tasks, :precheck_url, :string
    add_column :scheduled_tasks, :precheck_state, :jsonb, default: {}, null: false
    add_column :scheduled_tasks, :last_checked_at, :datetime
    add_column :scheduled_tasks, :last_check_result, :string
  end
end
