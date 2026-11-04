import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { jsonSchemaToZod } from "./json-schema-to-zod.js";
import { makeToolHandler } from "./tool-handler.js";

export { makeToolHandler, toolTimeoutMs, executeToolOnRails } from "./tool-handler.js";

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
