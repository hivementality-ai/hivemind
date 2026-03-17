import express from "express";
import Anthropic from "@anthropic-ai/sdk";
import { query } from "@anthropic-ai/claude-agent-sdk";
import { buildMcpServer } from "./mcp-tool-bridge.js";
import { existsSync, mkdirSync } from "fs";

const app = express();
app.use(express.json({ limit: "10mb" }));

const PORT = process.env.PORT || 3003;

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "sdk-proxy" });
});

// Chat endpoint — proxies requests to Anthropic API
// OAuth tokens (sk-ant-oat*) go through Claude Code via the Agent SDK
// API keys (sk-ant-api*) go directly to the Messages API
app.post("/v1/chat", async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Missing or invalid Authorization header" });
  }

  const token = authHeader.slice(7);
  const {
    messages,
    tools,
    model,
    max_tokens,
    temperature,
    thinking,
    system: systemPrompt,
    stream,
    agent_id,
    session_id,
    tool_definitions,
  } = req.body;

  const isOAuth = token.startsWith("sk-ant-oat");
  console.log(`[chat] token=${token.slice(0, 15)}... isOAuth=${isOAuth} stream=${stream} tools=${tool_definitions?.length || 0} agent=${agent_id} session=${session_id}`);

  try {
    if (isOAuth) {
      await handleOAuth(req, res, token, { messages, tools, model, max_tokens, temperature, thinking, systemPrompt, stream, agent_id, session_id, tool_definitions });
    } else {
      const client = new Anthropic({ apiKey: token });
      const params = buildApiParams({ messages, tools, model, max_tokens, temperature, thinking, systemPrompt });
      if (stream) {
        await handleApiStream(res, client, params);
      } else {
        await handleApiSync(res, client, params);
      }
    }
  } catch (err) {
    console.error("SDK proxy error:", err.message);
    if (!res.headersSent) {
      res.status(err.status || 500).json({ error: err.message });
    }
  }
});

// ─── OAuth path: Claude Code via Agent SDK ───

async function handleOAuth(_req, res, token, params) {
  const { messages, systemPrompt, model, stream, agent_id, session_id, tool_definitions } = params;

  // Extract system prompt text for structured passing
  let systemText = extractSystemPrompt(systemPrompt);

  // Build conversation transcript for context (SDK spawns fresh process each call)
  const conversationMessages = (messages || []).filter(m => m.role !== "system");
  if (conversationMessages.length > 1) {
    // Include all messages except the last user message (which becomes the prompt)
    const history = conversationMessages.slice(0, -1);
    if (history.length > 0) {
      const transcript = history.map(m => {
        const role = m.role === "user" ? "User" : "Assistant";
        const content = typeof m.content === "string" ? m.content : JSON.stringify(m.content);
        return `${role}: ${content}`;
      }).join("\n\n");

      systemText = (systemText || "") +
        "\n\n## Conversation History (this session)\n" +
        "The following is the conversation so far in this session. Use it to maintain context.\n\n" +
        transcript;
    }
  }

  // Extract the last user message as the prompt
  const lastUserMsg = conversationMessages
    .filter(m => m.role === "user")
    .pop();
  const prompt = typeof lastUserMsg?.content === "string"
    ? lastUserMsg.content
    : Array.isArray(lastUserMsg?.content)
      ? lastUserMsg.content.filter(b => b.type === "text").map(b => b.text).join("\n")
      : "Continue";

  const options = {};
  if (systemText) options.systemPrompt = systemText;
  if (model) options.model = model;
  options.env = { CLAUDE_CODE_OAUTH_TOKEN: token };
  options.stderr = (data) => console.error(`[claude-code stderr] ${data}`);

  // Set agent-scoped working directory for memory file access
  if (agent_id) {
    const memoryDir = `/app/agents-shared/.hivemind/agents/${agent_id}`;
    try {
      if (!existsSync(memoryDir)) {
        mkdirSync(memoryDir, { recursive: true });
      }
      options.cwd = memoryDir;
    } catch (err) {
      console.warn(`[oauth] Could not set cwd to ${memoryDir}: ${err.message}`);
    }
  }

  // Build MCP server from Hivemind tool definitions (if provided)
  const mcpToolNames = new Set();
  const sseForToolEvents = stream
    ? (type, data) => {
        console.log(`[oauth] Tool event: ${type}`, JSON.stringify(data).substring(0, 200));
        sendSSE(res, type, data);
      }
    : null;

  if (tool_definitions?.length && agent_id && session_id) {
    for (const def of tool_definitions) mcpToolNames.add(def.name);
    console.log(`[oauth] Building MCP server with ${tool_definitions.length} tools`);
    try {
      const mcpServers = buildMcpServer({
        tools: tool_definitions,
        agentId: agent_id,
        sessionId: session_id,
        onToolEvent: sseForToolEvents,
      });
      options.mcpServers = mcpServers;
      options.permissionMode = "bypassPermissions";
      options.allowDangerouslySkipPermissions = true;
      // Disable Claude Code's built-in Skill tool to avoid collision with
      // Hivemind's load_skill MCP tool (both load skill instructions, but
      // the built-in one doesn't know about Hivemind skills)
      options.disallowedTools = ["Skill"];
      console.log("[oauth] MCP server built successfully");
    } catch (err) {
      console.error("[oauth] MCP server build failed:", err);
    }
  }

  if (stream) {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });

    const activeTools = new Set();
    let isThinking = false;
    try {
      for await (const message of query({ prompt, options })) {
        console.log(`[query] message type=${message.type}`, JSON.stringify(message).substring(0, 300));

        if (message.type === "text") {
          if (isThinking) { sendSSE(res, "thinking_stop", {}); isThinking = false; }
          sendSSE(res, "content", { content: message.text });
        } else if (message.type === "thinking") {
          if (!isThinking) { sendSSE(res, "thinking_start", {}); isThinking = true; }
          sendSSE(res, "thinking", { thinking: message.thinking });
        } else if (message.type === "assistant") {
          if (isThinking) { sendSSE(res, "thinking_stop", {}); isThinking = false; }
          for (const block of message.message?.content || []) {
            if (block.type === "text" && block.text) {
              // When an assistant message arrives with text, any previously
              // active tools are done — emit tool_result for them
              for (const toolName of activeTools) {
                sendSSE(res, "tool_result", { tool: toolName, output: "", success: true });
              }
              activeTools.clear();
              sendSSE(res, "content", { content: block.text });
            } else if (block.type === "thinking" && block.thinking) {
              if (!isThinking) { sendSSE(res, "thinking_start", {}); isThinking = true; }
              sendSSE(res, "thinking", { thinking: block.thinking });
            } else if (block.type === "tool_use") {
              // MCP tools are handled by the bridge callbacks — only emit
              // tool_start here for Claude Code's own built-in tools
              if (!mcpToolNames.has(block.name)) {
                sendSSE(res, "tool_start", { tool: block.name, input: block.input || {} });
                activeTools.add(block.name);
              }
            }
          }
        } else if (message.type === "tool_progress") {
          if (isThinking) { sendSSE(res, "thinking_stop", {}); isThinking = false; }
          // Claude Code's own tool is actively running
          if (!activeTools.has(message.tool_name)) {
            sendSSE(res, "tool_start", { tool: message.tool_name, input: {} });
            activeTools.add(message.tool_name);
          }
        } else if (message.type === "result") {
          if (isThinking) { sendSSE(res, "thinking_stop", {}); isThinking = false; }
          // Close any remaining active tools
          for (const toolName of activeTools) {
            sendSSE(res, "tool_result", { tool: toolName, output: "", success: true });
          }
          activeTools.clear();
          const usage = message.usage || {};
          sendSSE(res, "result", { content: message.result, usage });
        }
      }
    } finally {
      sendSSE(res, "done", {});
      res.end();
    }
  } else {
    let fullContent = "";
    let usage = {};

    for await (const message of query({ prompt, options })) {
      if (message.type === "text") {
        fullContent += message.text || "";
      } else if (message.type === "assistant") {
        for (const block of message.message?.content || []) {
          if (block.type === "text" && block.text) {
            fullContent += block.text;
          }
        }
      } else if (message.type === "result") {
        fullContent = message.result || fullContent;
        if (message.usage) usage = message.usage;
      }
    }

    res.json({ content: fullContent || null, thinking: null, tool_calls: null, usage });
  }
}

function extractSystemPrompt(systemPrompt) {
  if (!systemPrompt) return null;
  if (typeof systemPrompt === "string") return systemPrompt;
  if (Array.isArray(systemPrompt)) {
    return systemPrompt.map(b => b.text).filter(Boolean).join("\n\n");
  }
  return String(systemPrompt);
}

// ─── API key path: direct Anthropic SDK ───

function buildApiParams({ messages, tools, model, max_tokens, temperature, thinking, systemPrompt }) {
  const params = {
    model: model || "claude-sonnet-4-5-20250929",
    messages: messages || [],
    max_tokens: max_tokens || 8192,
  };

  if (systemPrompt) params.system = systemPrompt;
  if (tools?.length > 0) params.tools = tools;
  if (temperature !== undefined) params.temperature = temperature;

  if (thinking?.type === "enabled") {
    params.thinking = thinking;
    delete params.temperature;
  }

  return params;
}

async function handleApiSync(res, client, params) {
  const response = await client.messages.create(params);

  let content = null;
  let thinkingContent = null;
  const toolCalls = [];

  for (const block of response.content) {
    if (block.type === "text") content = block.text;
    else if (block.type === "thinking") thinkingContent = block.thinking;
    else if (block.type === "tool_use") {
      toolCalls.push({ id: block.id, name: block.name, input: block.input || {} });
    }
  }

  res.json({
    content,
    thinking: thinkingContent,
    tool_calls: toolCalls.length > 0 ? toolCalls : null,
    usage: {
      input_tokens: response.usage?.input_tokens,
      output_tokens: response.usage?.output_tokens,
      cache_creation_input_tokens: response.usage?.cache_creation_input_tokens,
      cache_read_input_tokens: response.usage?.cache_read_input_tokens,
    },
  });
}

async function handleApiStream(res, client, params) {
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });

  const stream = client.messages.stream(params);
  let currentBlockType = null;

  stream.on("contentBlockStart", (event) => {
    currentBlockType = event.content_block?.type;
    if (currentBlockType === "thinking") sendSSE(res, "thinking_start", {});
  });

  stream.on("contentBlockDelta", (event) => {
    if (currentBlockType === "thinking" && event.delta?.thinking) {
      sendSSE(res, "thinking", { thinking: event.delta.thinking });
    } else if (event.delta?.text) {
      sendSSE(res, "content", { content: event.delta.text });
    }
  });

  stream.on("contentBlockStop", () => {
    if (currentBlockType === "thinking") sendSSE(res, "thinking_stop", {});
    currentBlockType = null;
  });

  try {
    const finalMessage = await stream.finalMessage();
    sendSSE(res, "result", {
      usage: {
        input_tokens: finalMessage.usage?.input_tokens,
        output_tokens: finalMessage.usage?.output_tokens,
        cache_creation_input_tokens: finalMessage.usage?.cache_creation_input_tokens,
        cache_read_input_tokens: finalMessage.usage?.cache_read_input_tokens,
      },
    });
  } catch (err) {
    sendSSE(res, "error", { error: err.message });
  } finally {
    sendSSE(res, "done", {});
    res.end();
  }
}

function sendSSE(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

// Catch unhandled errors so the process doesn't crash silently
process.on("uncaughtException", (err) => {
  console.error("[FATAL] Uncaught exception:", err);
});
process.on("unhandledRejection", (err) => {
  console.error("[FATAL] Unhandled rejection:", err);
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`SDK proxy listening on port ${PORT}`);
});
