# frozen_string_literal: true

module HashtagActions
  module Actions
    class Summarize < Base
      def execute
        # Augment action — inject a summarize instruction, let LLM handle it
        transcript = session.transcript || []

        if transcript.size < 3
          return { response: "Not enough conversation to summarize yet.", status: "too_short" }
        end

        {
          prompt_addon: "The user has requested a summary of this conversation. Provide a clear, concise summary of the key points discussed so far.",
          bypass: false,
          status: "augmented"
        }
      end
    end
  end
end
