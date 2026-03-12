# frozen_string_literal: true

module Plugins
  # Event-based hook system for plugins. Handlers are registered per event
  # and invoked sequentially when {trigger} is called.
  class Hooks
    VALID_EVENTS = %w[
      before_chat after_chat
      before_tool_call after_tool_call
      agent_created session_created
    ].freeze

    class << self
      # Registers a handler class for a lifecycle event.
      #
      # @param event [String] one of {VALID_EVENTS}
      # @param handler_class [Class, String] handler class (or its name for lazy constantize)
      # @raise [ArgumentError] if the event is not in {VALID_EVENTS}
      def register(event, handler_class)
        event = event.to_s
        unless VALID_EVENTS.include?(event)
          raise ArgumentError, "Unknown hook event: #{event} (valid: #{VALID_EVENTS.join(', ')})"
        end

        handler = handler_class.is_a?(String) ? handler_class.constantize : handler_class
        handlers[event] ||= []
        handlers[event] << handler unless handlers[event].include?(handler)
      end

      # @param event [String] lifecycle event name
      # @param handler_class [Class, String] handler to remove
      def unregister(event, handler_class)
        event = event.to_s
        handler = handler_class.is_a?(String) ? handler_class.constantize : handler_class
        handlers[event]&.delete(handler)
      end

      # Invokes all handlers for the given event. Failures are logged but
      # do not halt execution of subsequent handlers.
      #
      # @param event [String] lifecycle event name
      # @param payload [Hash] context passed to each handler's +#call+ method
      # @return [ServiceResponse] success with +:results+ array from each handler
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

      # @param event [String] lifecycle event name
      # @return [Array<Class>] handler classes registered for this event
      def registered_for(event)
        handlers[event.to_s] || []
      end

      # Clears all registered handlers. Intended for tests.
      # @return [Hash] empty hash
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
