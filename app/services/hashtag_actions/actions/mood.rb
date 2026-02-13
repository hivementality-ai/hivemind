# frozen_string_literal: true

module HashtagActions
  module Actions
    class Mood < Base
      def execute
        return { response: "Set what mood? Use: #mood <style instruction>", status: "no_payload" } if payload.blank?

        # Store mood as session metadata so it persists across messages
        meta = session.metadata || {}
        meta["mood"] = payload
        session.update!(metadata: meta)

        {
          prompt_addon: "IMPORTANT STYLE OVERRIDE: For the rest of this conversation, adjust your communication style: #{payload}. This was requested by the user.",
          bypass: false,
          response: "Mood set: #{payload.truncate(80)}",
          status: "set"
        }
      end
    end
  end
end
