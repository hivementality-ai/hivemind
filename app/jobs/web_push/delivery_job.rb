# frozen_string_literal: true

module WebPush
  class DeliveryJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(subscription_id, payload_json)
      subscription = PushSubscription.find_by(id: subscription_id)
      return unless subscription

      begin
        ::WebPush.payload_send(
          message: payload_json,
          endpoint: subscription.endpoint,
          p256dh: subscription.p256dh,
          auth: subscription.auth,
          vapid: {
            subject: "mailto:#{vapid_contact}",
            public_key: ENV.fetch("VAPID_PUBLIC_KEY"),
            private_key: ENV.fetch("VAPID_PRIVATE_KEY")
          },
          ttl: 86400
        )
      rescue ::WebPush::ExpiredSubscription, ::WebPush::InvalidSubscription
        # Subscription is no longer valid, clean it up
        subscription.destroy
      rescue ::WebPush::PayloadTooLarge
        Rails.logger.warn("[WebPush] Payload too large for subscription #{subscription.id}")
      end
    end

    private

    def vapid_contact
      ENV.fetch("VAPID_CONTACT", "admin@hivemind.local")
    end
  end
end
