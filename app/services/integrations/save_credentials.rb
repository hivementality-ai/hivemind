# frozen_string_literal: true

module Integrations
  class SaveCredentials
    def self.call(namespace:, fields:, required: [])
      new(namespace:, fields:, required:).call
    end

    def initialize(namespace:, fields:, required: [])
      @namespace = namespace
      @fields = fields
      @required = required
    end

    def call
      missing = @required.select { |key| @fields[key].blank? }
      if missing.any?
        return ServiceResponse.failure(error: "#{missing.map { |k| k.to_s.humanize }.join(', ')} required")
      end

      @fields.each do |key, value|
        next if value.blank?

        entry = VaultEntry.find_or_initialize_by(namespace: @namespace, key: key.to_s)
        entry.value = value
        unless entry.save
          return ServiceResponse.failure(error: "Failed to save #{key}: #{entry.errors.full_messages.join(', ')}")
        end
      end

      ServiceResponse.success(data: { namespace: @namespace, fields_saved: @fields.keys.count(&:present?) })
    rescue StandardError => e
      ServiceResponse.failure(error: e.message)
    end
  end
end