// Tracks token-level stream events so the whole-message text that follows
// them is not forwarded a second time.

/**
 * Per-turn tracker for `includePartialMessages` output.
 *
 * Feed every `stream_event` to `textDelta`; pass each text block of the later
 * whole `assistant` message to `remainder` to get the part of it that was not
 * already streamed.
 */
export function createPartialStreamTracker() {
  let streamed = "";

  return {
    /**
     * Visible text carried by a stream event, or null for anything else
     * (thinking deltas, tool input deltas, subagent events, block bookkeeping).
     * @param {object} message an SDK message
     * @returns {string|null}
     */
    textDelta(message) {
      if (message?.type !== "stream_event" || message.parent_tool_use_id) return null;
      const event = message.event;
      if (event?.type === "message_start") {
        streamed = "";
        return null;
      }
      if (event?.type !== "content_block_delta") return null;
      if (event.delta?.type !== "text_delta" || !event.delta.text) return null;
      streamed += event.delta.text;
      return event.delta.text;
    },

    /**
     * The unsent tail of a whole-message text block.
     * @param {string} text the block's full text
     * @returns {string} empty when the block was already streamed in full
     */
    remainder(text) {
      const pending = streamed;
      if (!pending) return text;
      if (text.startsWith(pending)) {
        streamed = "";
        return text.slice(pending.length);
      }
      if (pending.startsWith(text)) {
        streamed = pending.slice(text.length);
        return "";
      }
      streamed = "";
      return "";
    },
  };
}
