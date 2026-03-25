# frozen_string_literal: true

module WebPush
  class VapidKeys
    NAMESPACE = "web_push"

    class << self
      def public_key
        ensure_keys!
        VaultEntry.resolve(namespace: NAMESPACE, key: "vapid_public_key")&.encrypted_value
      end

      def private_key
        ensure_keys!
        VaultEntry.resolve(namespace: NAMESPACE, key: "vapid_private_key")&.encrypted_value
      end

      def configured?
        public_key.present? && private_key.present?
      end

      private

      def ensure_keys!
        return if VaultEntry.find_by(namespace: NAMESPACE, key: "vapid_public_key")

        keys = ::WebPush.generate_key

        VaultEntry.find_or_create_by!(namespace: NAMESPACE, key: "vapid_public_key") do |entry|
          entry.encrypted_value = keys.public_key
        end

        VaultEntry.find_or_create_by!(namespace: NAMESPACE, key: "vapid_private_key") do |entry|
          entry.encrypted_value = keys.private_key
        end

        Rails.logger.info("[WebPush] VAPID keys auto-generated and stored in vault")
      rescue StandardError => e
        Rails.logger.warn("[WebPush] Failed to auto-generate VAPID keys: #{e.message}")
      end
    end
  end
end
