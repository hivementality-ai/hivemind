# frozen_string_literal: true

# Shared helpers for the auto-title jobs (SessionTitleJob, TeamChatTitleJob).
#
# The transcript must be handed to the model as *data to label*, not as a chat
# turn to answer — otherwise a cheap model (Haiku) will sometimes reply to the
# conversation instead of titling it, e.g. "I'm Claude, an AI assistant made by
# Anthropic...", and that reply ends up as the chat title.
module TitleSanitizer
  module_function

  # Wrap the transcript so the model titles it rather than continuing it.
  def request(conversation)
    "Write a title for the conversation below. Reply with only the title.\n\n" \
    "<transcript>\n#{conversation}\n</transcript>"
  end

  # True when the model answered the conversation (identity/refusal leak) instead
  # of returning a title. Such output must never become a title.
  REFUSAL_PATTERNS = /
    I'm\s+Claude | I\s+am\s+Claude | AI\s+assistant | \bAnthropic\b |
    as\s+an\s+AI | I\s+appreciate | I\s+should\s+clarify | I\s+can(?:no|'?)t
  /xi

  def refusal?(text)
    text.match?(REFUSAL_PATTERNS)
  end
end
