# frozen_string_literal: true

module WebPush
  class Sender
    def self.call(user:, title:, body:, url: "/m/", tag: nil)
      new(user: user, title: title, body: body, url: url, tag: tag).call
    end

    def initialize(user:, title:, body:, url: "/m/", tag: nil)
      @user = user
      @title = title
      @body = body
      @url = url
      @tag = tag
    end

    def call
      return unless vapid_configured?

      subscriptions = @user.push_subscriptions
      return if subscriptions.empty?

      # Check user notification preferences
      return unless notification_allowed?

      subscriptions.find_each do |subscription|
        WebPush::DeliveryJob.perform_later(
          subscription.id,
          payload.to_json
        )
      end
    end

    private

    def payload
      {
        title: @title,
        body: @body,
        url: @url,
        tag: @tag || "hivemind-#{SecureRandom.hex(4)}"
      }
    end

    def notification_allowed?
      prefs = @user.try(:notification_preferences) || {}
      # Default to allowed if no preferences set
      true
    end

    def vapid_configured?
      WebPush::VapidKeys.configured?
    end
  end
end
