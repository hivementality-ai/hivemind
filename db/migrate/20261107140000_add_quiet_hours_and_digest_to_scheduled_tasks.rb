# frozen_string_literal: true

# Quiet hours window, optional daily digest hour, and the changes a watch is holding back until release.
class AddQuietHoursAndDigestToScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :scheduled_tasks, :quiet_start_hour, :integer
    add_column :scheduled_tasks, :quiet_end_hour, :integer
    add_column :scheduled_tasks, :digest_hour, :integer
    add_column :scheduled_tasks, :held_changes, :jsonb, default: {}, null: false
  end
end
