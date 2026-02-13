# frozen_string_literal: true

module HashtagActions
  module Actions
    class Private < Base
      def execute
        # Private messages bypass transcript storage entirely.
        # The processor will pass the clean message to the LLM but won't store it.
        # We mark it so ChatStreamJob knows not to persist.

        {
          prompt_addon: "This message is private and should not be referenced in future conversations. Respond normally but know this exchange is ephemeral.",
          bypass: false,
          status: "private",
          metadata: { private: true }
        }
      end
    end
  end
end
