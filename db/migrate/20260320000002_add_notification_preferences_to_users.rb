class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notification_preferences, :jsonb, default: {
      "agent_responses" => true,
      "task_completions" => true,
      "budget_alerts" => true,
      "heartbeat_findings" => false
    }, null: false
  end
end
