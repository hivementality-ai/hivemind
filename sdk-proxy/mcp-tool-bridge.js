import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { jsonSchemaToZod } from "./json-schema-to-zod.js";

const RAILS_INTERNAL_URL = process.env.RAILS_INTERNAL_URL || "http://app:3000";
const INTERNAL_API_SECRET = process.env.INTERNAL_API_SECRET;

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
      async (args) => {
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
          } else {
            return {
              content: [{ type: "text", text: `Error: ${result.error}` }],
              isError: true,
            };
          }
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
      }
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
 * HTTP POST to Rails internal tools endpoint.
 */
async function executeToolOnRails({ toolName, input, agentId, sessionId }) {
  const url = `${RAILS_INTERNAL_URL}/internal/tools/execute`;

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
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Rails internal API error (${response.status}): ${body}`);
  }

  return response.json();
}
