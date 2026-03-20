# frozen_string_literal: true

module Mobile
  class SettingsController < BaseController
    def index
      @notification_preferences = current_user.try(:notification_preferences) || {
        "agent_responses" => true,
        "task_completions" => true,
        "budget_alerts" => true,
        "heartbeat_findings" => false
      }
    end

    def push_subscription
      subscription_data = params.require(:subscription).permit(:endpoint, :p256dh, :auth)

      sub = PushSubscription.find_or_initialize_by(
        user: current_user,
        endpoint: subscription_data[:endpoint]
      )
      sub.update!(
        p256dh: subscription_data[:p256dh],
        auth: subscription_data[:auth]
      )

      render json: { status: "subscribed" }
    rescue ActiveRecord::RecordNotFound, ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
