class UpdateScheduledTasksForConfirmation < ActiveRecord::Migration[8.1]
  def change
    # Fix last_error_at type (STRING → DATETIME) using USING clause
    if column_exists?(:scheduled_tasks, :last_error_at)
      change_column :scheduled_tasks, :last_error_at, :datetime, using: "last_error_at::timestamp(6) without time zone"
    end

    # Add new columns for confirmation system
    add_column :scheduled_tasks, :description, :text, if_not_exists: true
    add_column :scheduled_tasks, :confirmation_status, :string, default: "active", if_not_exists: true
    add_column :scheduled_tasks, :job_params, :jsonb, if_not_exists: true

    # Add index for efficient queries
    add_index :scheduled_tasks, [ :agent_id, :confirmation_status ], if_not_exists: true
  end
end
