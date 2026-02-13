# frozen_string_literal: true

module HashtagActions
  module Actions
    class Reset < Base
      def execute
        message_count = (session.transcript || []).size
        session.update!(transcript: [], input_tokens: 0, output_tokens: 0, total_tokens: 0)

        { response: "Session reset. Cleared #{message_count} messages. Starting fresh.", status: "reset" }
      end
    end
  end
end
