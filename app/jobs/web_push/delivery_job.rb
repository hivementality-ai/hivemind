# frozen_string_literal: true

module WebPush
  class DeliveryJob < ApplicationJob
    queue_as :system
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(subscription_id, payload_json)
      subscription = PushSubscription.find_by(id: subscription_id)
      return unless subscription

      public_key = WebPush::VapidKeys.public_key
      private_key = WebPush::VapidKeys.private_key
      return unless public_key && private_key

      begin
        ::WebPush.payload_send(
          message: payload_json,
          endpoint: subscription.endpoint,
          p256dh: subscription.p256dh,
          auth: subscription.auth,
          vapid: {
            subject: "mailto:#{vapid_contact}",
            public_key: public_key,
            private_key: private_key
          },
          ttl: 86400
        )
      rescue ::WebPush::ExpiredSubscription, ::WebPush::InvalidSubscription
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
