# frozen_string_literal: true

# Raised when the LLM provider rejects a request because the prompt exceeds
# its context window. Agents::ToolLoop catches this to trigger an
# Agents::AutoCompact and retry once before giving up.
class PromptTooLongError < StandardError
end
