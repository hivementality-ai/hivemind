# frozen_string_literal: true

module HashtagActions
  module Actions
    class Voice < Base
      def execute
        text = payload.presence || clean_message

        return { response: "Say what? Use: #voice <text to speak>", status: "no_payload" } if text.blank?

        {
          prompt_addon: "The user wants your response as audio. Respond naturally and conversationally — your text will be converted to speech via TTS. Keep it concise and spoken-word friendly.",
          bypass: false,
          status: "augmented"
        }
      end
    end
  end
end
