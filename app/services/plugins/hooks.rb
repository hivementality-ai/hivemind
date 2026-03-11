# frozen_string_literal: true

module Plugins
  class Hooks
    VALID_EVENTS = %w[
      before_chat after_chat
      before_tool_call after_tool_call
      agent_created session_created
    ].freeze

    class << self
      def register(event, handler_class)
        event = event.to_s
        unless VALID_EVENTS.include?(event)
          raise ArgumentError, "Unknown hook event: #{event} (valid: #{VALID_EVENTS.join(', ')})"
        end

        handler = handler_class.is_a?(String) ? handler_class.constantize : handler_class
        handlers[event] ||= []
        handlers[event] << handler unless handlers[event].include?(handler)
      end

      def unregister(event, handler_class)
        event = event.to_s
        handler = handler_class.is_a?(String) ? handler_class.constantize : handler_class
        handlers[event]&.delete(handler)
      end

      def trigger(event, payload = {})
        event = event.to_s
        results = []

        (handlers[event] || []).each do |handler|
          result = handler.new.call(payload)
          results << result
        rescue StandardError => e
          Rails.logger.error("[Plugins::Hooks] #{handler} failed on #{event}: #{e.message}")
          results << ServiceResponse.failure(error: "#{handler}: #{e.message}")
        end

        ServiceResponse.success(data: { results: results })
      end

      def registered_for(event)
        handlers[event.to_s] || []
      end

      def reset!
        @handlers = {}
      end

      private

      def handlers
        @handlers ||= {}
      end
    end
  end
end
