# frozen_string_literal: true

module HashtagActions
  module Actions
    class Help < Base
      HELP_TEXT = <<~HELP
        Hashtag Actions:

        #remember <text> — Save something to long-term memory
        #forget <keyword> — Remove memories matching a keyword
        #search <query> — Search agent memories
        #todo <task> — Add a task to the checklist
        #schedule <time> <task> — Schedule a reminder (e.g., #schedule 2h Check deploy)
        #summarize — Summarize the current conversation
        #status — Show agent info and session stats
        #reset — Clear conversation history
        #mood <style> — Change the agent's tone (e.g., #mood be more casual)
        #voice <text> — Reply as audio
        #image <prompt> — Generate an image
        #handoff @agent — Transfer conversation to another agent
        #delegate @agent <task> — Ask another agent to do something
        #private <text> — Send a message that won't be logged
        #approve — Approve a pending action
        #deny — Deny a pending action
        #help — Show this message

        Compose multiple: #remember #todo Fix the login bug by Friday
      HELP

      def execute
        { response: HELP_TEXT.strip, status: "ok" }
      end
    end
  end
end
