# frozen_string_literal: true

module Mobile
  class SettingsController < BaseController
    VALID_PREF_KEYS = %w[agent_responses task_completions budget_alerts heartbeat_findings].freeze
    DEFAULT_PREFS = {
      "agent_responses" => true,
      "task_completions" => true,
      "budget_alerts" => true,
      "heartbeat_findings" => false
    }.freeze

    def index
      @notification_preferences = DEFAULT_PREFS.merge(
        current_user.try(:notification_preferences) || {}
      )
    end

    def update_preferences
      prefs = {}
      VALID_PREF_KEYS.each do |key|
        prefs[key] = params.dig(:preferences, key) == "1"
      end

      current_user.update!(notification_preferences: prefs)
      redirect_to mobile_settings_path, notice: "Preferences saved."
    rescue StandardError => e
      redirect_to mobile_settings_path, alert: "Failed to save: #{e.message}"
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
    rescue ActiveRecord::RecordInvalid, ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
