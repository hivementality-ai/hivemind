// Calls a Hivemind tool on Rails for the SDK, with a per-call timeout.

const RAILS_INTERNAL_URL = process.env.RAILS_INTERNAL_URL || "http://app:3000";
const INTERNAL_API_SECRET = process.env.INTERNAL_API_SECRET;
const DEFAULT_TOOL_TIMEOUT_MS = 1_860_000;

/**
 * Per-callback timeout, read on each call so tests and operators can change it.
 * @returns {number} milliseconds
 */
export function toolTimeoutMs() {
  const parsed = Number.parseInt(process.env.SDK_PROXY_TOOL_TIMEOUT_MS, 10);
  return parsed > 0 ? parsed : DEFAULT_TOOL_TIMEOUT_MS;
}

/**
 * Build the MCP handler for one tool. Failures (timeout, non-2xx, connection
 * refused) come back as an error result so the model's turn continues.
 *
 * @param {Object} opts
 * @param {string} opts.name
 * @param {string} opts.agentId
 * @param {string} opts.sessionId
 * @param {Function} [opts.onToolEvent]
 * @returns {(args: Object) => Promise<Object>}
 */
export function makeToolHandler({ name, agentId, sessionId, onToolEvent }) {
  return async (args) => {
    console.log(`[mcp-bridge] Tool called: ${name}`, JSON.stringify(args).substring(0, 500));
    onToolEvent?.("tool_start", { tool: name, input: args });

    try {
      const result = await executeToolOnRails({
        toolName: name,
        input: args,
        agentId,
        sessionId,
      });

      onToolEvent?.("tool_result", {
        tool: name,
        input: args,
        output: result.output || "",
        success: result.success,
      });

      if (result.success) {
        return {
          content: [{ type: "text", text: result.output || "" }],
        };
      }
      return {
        content: [{ type: "text", text: `Error: ${result.error}` }],
        isError: true,
      };
    } catch (err) {
      onToolEvent?.("tool_result", {
        tool: name,
        output: err.message,
        success: false,
      });

      return {
        content: [{ type: "text", text: `Tool execution failed: ${err.message}` }],
        isError: true,
      };
    }
  };
}

/**
 * HTTP POST to Rails internal tools endpoint, aborted after the callback
 * timeout. Throws on timeout, connection failure, or a non-2xx response.
 */
export async function executeToolOnRails({ toolName, input, agentId, sessionId }) {
  const url = `${RAILS_INTERNAL_URL}/internal/tools/execute`;
  const timeoutMs = toolTimeoutMs();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${INTERNAL_API_SECRET}`,
      },
      body: JSON.stringify({
        tool_name: toolName,
        input,
        agent_id: agentId,
        session_id: sessionId,
      }),
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Rails internal API error (${response.status}): ${body}`);
    }

    return await response.json();
  } catch (err) {
    if (controller.signal.aborted) {
      throw new Error(`tool ${toolName} timed out after ${Math.round(timeoutMs / 1000)}s`);
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}
