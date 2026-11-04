class AddNeedsInputAndErrorsToNotificationPreferencesDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :notification_preferences, from: {
      "agent_responses" => true,
      "task_completions" => true,
      "budget_alerts" => true,
      "heartbeat_findings" => false
    }, to: {
      "agent_responses" => true,
      "task_completions" => true,
      "budget_alerts" => true,
      "heartbeat_findings" => false,
      "needs_input" => true,
      "errors" => true
    }
  end
end
