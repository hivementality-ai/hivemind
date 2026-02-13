# frozen_string_literal: true

module HashtagActions
  module Actions
    class Base
      def self.call(agent:, session:, payload: nil, user: nil, clean_message: nil, **_opts)
        new(agent:, session:, payload:, user:, clean_message:).execute
      end

      def initialize(agent:, session:, payload: nil, user: nil, clean_message: nil)
        @agent = agent
        @session = session
        @payload = payload
        @user = user
        @clean_message = clean_message
      end

      # Subclasses must implement this.
      # Returns a Hash with:
      #   response:     String (direct reply to user, optional)
      #   prompt_addon: String (injected into system prompt, optional)
      #   bypass:       Boolean (override bypass decision, optional)
      #   status:       String (for side_effects log)
      def execute
        raise NotImplementedError
      end

      private

      attr_reader :agent, :session, :payload, :user, :clean_message
    end
  end
end
