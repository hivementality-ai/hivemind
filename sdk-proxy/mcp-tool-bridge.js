import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { jsonSchemaToZod } from "./json-schema-to-zod.js";

const RAILS_INTERNAL_URL = process.env.RAILS_INTERNAL_URL || "http://app:3000";
const INTERNAL_API_SECRET = process.env.INTERNAL_API_SECRET;
const DEFAULT_TOOL_TIMEOUT_MS = 120_000;

/**
 * Per-callback timeout, read on each call so tests and operators can change it.
 * @returns {number} milliseconds
 */
function toolTimeoutMs() {
  const parsed = Number.parseInt(process.env.SDK_PROXY_TOOL_TIMEOUT_MS, 10);
  return parsed > 0 ? parsed : DEFAULT_TOOL_TIMEOUT_MS;
}

/**
 * Build an MCP server from Hivemind tool definitions.
 *
 * Each tool handler makes an HTTP POST to Rails' internal tools endpoint,
 * which executes Tools::Executor and returns the result.
 *
 * @param {Object} opts
 * @param {Array}  opts.tools          - Tool definitions from Rails (name, description, input_schema)
 * @param {string} opts.agentId        - Hivemind agent ID
 * @param {string} opts.sessionId      - Hivemind session ID
 * @param {Function} opts.onToolEvent  - Callback for tool activity (type, data) => void
 * @returns {Record<string, McpSdkServerConfigWithInstance>}
 */
export function buildMcpServer({ tools, agentId, sessionId, onToolEvent }) {
  if (!tools?.length) return {};

  const mcpTools = [];

  for (const def of tools) {
    const name = def.name;
    const description = def.description || `Execute ${name}`;
    const schema = def.input_schema || { properties: {}, required: [] };

    let zodShape;
    try {
      zodShape = jsonSchemaToZod(schema);
    } catch (err) {
      console.warn(`[mcp-bridge] Failed to convert schema for ${name}:`, err.message);
      zodShape = {};
    }

    const mcpTool = tool(
      name,
      description,
      zodShape,
      makeToolHandler({ name, agentId, sessionId, onToolEvent })
    );

    mcpTools.push(mcpTool);
  }

  console.log(`[mcp-bridge] Registered ${mcpTools.length} MCP tools: ${mcpTools.map(t => t.name || 'unnamed').join(', ').substring(0, 200)}`);

  const server = createSdkMcpServer({
    name: "hivemind-tools",
    version: "1.0.0",
    tools: mcpTools,
  });

  return { "hivemind-tools": server };
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
