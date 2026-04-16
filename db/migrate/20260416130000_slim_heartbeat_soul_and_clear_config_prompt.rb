# frozen_string_literal: true

class SlimHeartbeatSoulAndClearConfigPrompt < ActiveRecord::Migration[8.0]
  NEW_SOUL = <<~PROMPT.strip
    You are the system heartbeat assistant. You wake up periodically to check on things.

    Your job:
    - Work through any checklist tasks you receive
    - Check your memories (memory_search) for context from previous heartbeats
    - Delegate work to the right teammate using the delegate tool — don't do everything yourself
    - Save important findings to memory so you remember them next time
    - Standing checklist items recur every heartbeat — do not remove them
    - One-off checklist items should be removed via heartbeat_write after handling
    - If something needs human attention, surface it clearly
    - Be concise and action-oriented

    If nothing needs attention, reply with exactly: HEARTBEAT_OK
  PROMPT

  def up
    # Update the system assistant's soul to the leaner version.
    execute <<~SQL
      UPDATE agents
      SET system_prompt = #{ActiveRecord::Base.connection.quote(NEW_SOUL)},
          updated_at = NOW()
      WHERE system_agent = TRUE
        AND name = 'Assistant'
    SQL

    # Clear the bloated custom prompt blob from the heartbeat config Setting.
    # The prompt field was used to dump teammate lists and behavioral instructions
    # that now live in the soul. We set it to nil so no custom prompt is injected.
    raw = Setting.find_by(key: "heartbeat")&.value
    return if raw.blank?

    config = JSON.parse(raw)
    config.delete("prompt")
    Setting.find_by(key: "heartbeat")&.update_columns(value: config.to_json, updated_at: Time.current)
  rescue JSON::ParserError
    # If the setting is corrupt, leave it alone.
  end

  def down
    # No safe rollback for the soul change.
    # The prompt field can be restored manually via the Heartbeat settings UI.
  end
end
