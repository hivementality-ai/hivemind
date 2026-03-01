import express from "express";
import Anthropic from "@anthropic-ai/sdk";
import { query } from "@anthropic-ai/claude-agent-sdk";

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
  } = req.body;

  const isOAuth = token.startsWith("sk-ant-oat");

  try {
    if (isOAuth) {
      await handleOAuth(req, res, token, { messages, tools, model, max_tokens, temperature, thinking, systemPrompt, stream });
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
  const { messages, systemPrompt, model, stream } = params;

  // Set the OAuth token for Claude Code to pick up
  process.env.CLAUDE_CODE_OAUTH_TOKEN = token;
  // Clear API key so Claude Code doesn't try to use it
  delete process.env.ANTHROPIC_API_KEY;

  const prompt = buildPrompt(messages, systemPrompt);
  const options = {};
  if (model) options.model = model;

  if (stream) {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });

    try {
      for await (const message of query({ prompt, options })) {
        if (message.type === "text") {
          sendSSE(res, "content", { content: message.text });
        } else if (message.type === "thinking") {
          sendSSE(res, "thinking", { thinking: message.thinking });
        } else if (message.type === "result") {
          sendSSE(res, "result", { content: message.result, usage: message.usage });
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
      } else if (message.type === "result") {
        fullContent = message.result || fullContent;
        if (message.usage) usage = message.usage;
      }
    }

    res.json({ content: fullContent || null, thinking: null, tool_calls: null, usage });
  }
}

// Build a text prompt from chat messages for the Agent SDK
function buildPrompt(messages, systemPrompt) {
  const parts = [];

  if (systemPrompt) {
    const text = typeof systemPrompt === "string"
      ? systemPrompt
      : systemPrompt.map((b) => b.text).join("\n");
    parts.push(`[System]\n${text}`);
  }

  for (const msg of messages) {
    const role = msg.role;
    const content = typeof msg.content === "string" ? msg.content : JSON.stringify(msg.content);
    if (role === "system") continue;
    if (role === "user") parts.push(`[User]\n${content}`);
    else if (role === "assistant") parts.push(`[Assistant]\n${content}`);
    else if (role === "tool") parts.push(`[Tool Result (${msg.tool_use_id})]\n${content}`);
  }

  return parts.join("\n\n");
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

app.listen(PORT, "0.0.0.0", () => {
  console.log(`SDK proxy listening on port ${PORT}`);
});
