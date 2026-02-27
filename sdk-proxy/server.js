const express = require("express");
const { query, ClaudeAgentOptions } = require("@anthropic-ai/claude-agent-sdk");

const app = express();
app.use(express.json({ limit: "10mb" }));

const PORT = process.env.PORT || 3003;

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "sdk-proxy" });
});

// Chat endpoint — proxies requests through the Agent SDK
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

  // Set token for the SDK to pick up
  process.env.ANTHROPIC_API_KEY = token;

  try {
    if (stream) {
      await handleStream(req, res, { messages, tools, model, max_tokens, temperature, thinking, systemPrompt });
    } else {
      await handleSync(req, res, { messages, tools, model, max_tokens, temperature, thinking, systemPrompt });
    }
  } catch (err) {
    console.error("SDK proxy error:", err.message);
    if (!res.headersSent) {
      res.status(500).json({ error: err.message });
    }
  }
});

async function handleSync(_req, res, params) {
  const { messages, tools, model, max_tokens, temperature, thinking, systemPrompt } = params;

  // Build the prompt from messages
  const prompt = buildPrompt(messages, systemPrompt);
  const options = buildOptions({ tools, model, max_tokens, temperature, thinking });

  let fullContent = "";
  let fullThinking = "";
  let toolCalls = [];
  let usage = {};

  for await (const message of query({ prompt, options })) {
    if (message.type === "text") {
      fullContent += message.text || "";
    } else if (message.type === "thinking") {
      fullThinking += message.thinking || "";
    } else if (message.type === "tool_use") {
      toolCalls.push({
        id: message.id,
        name: message.name,
        input: message.input || {},
      });
    } else if (message.type === "result") {
      fullContent = message.result || fullContent;
      if (message.usage) usage = message.usage;
    } else if (message.type === "usage") {
      usage = message;
    }
  }

  res.json({
    content: fullContent || null,
    thinking: fullThinking || null,
    tool_calls: toolCalls.length > 0 ? toolCalls : null,
    usage,
  });
}

async function handleStream(_req, res, params) {
  const { messages, tools, model, max_tokens, temperature, thinking, systemPrompt } = params;

  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });

  const prompt = buildPrompt(messages, systemPrompt);
  const options = buildOptions({ tools, model, max_tokens, temperature, thinking });

  try {
    for await (const message of query({ prompt, options })) {
      if (message.type === "text") {
        sendSSE(res, "content", { content: message.text });
      } else if (message.type === "thinking") {
        sendSSE(res, "thinking", { thinking: message.thinking });
      } else if (message.type === "tool_use") {
        sendSSE(res, "tool_use", {
          id: message.id,
          name: message.name,
          input: message.input,
        });
      } else if (message.type === "result") {
        sendSSE(res, "result", { content: message.result, usage: message.usage });
      }
    }
  } finally {
    sendSSE(res, "done", {});
    res.end();
  }
}

// Build a text prompt from the messages array (Anthropic chat format → single prompt)
function buildPrompt(messages, systemPrompt) {
  const parts = [];

  if (systemPrompt) {
    parts.push(`[System]\n${typeof systemPrompt === "string" ? systemPrompt : systemPrompt.map((b) => b.text).join("\n")}`);
  }

  for (const msg of messages) {
    const role = msg.role;
    const content = typeof msg.content === "string" ? msg.content : JSON.stringify(msg.content);

    if (role === "system") continue; // already handled
    if (role === "user") parts.push(`[User]\n${content}`);
    else if (role === "assistant") parts.push(`[Assistant]\n${content}`);
    else if (role === "tool") parts.push(`[Tool Result (${msg.tool_use_id})]\n${content}`);
  }

  return parts.join("\n\n");
}

// Build SDK options from request params
function buildOptions({ tools, model, max_tokens, temperature, thinking }) {
  const options = {};

  if (model) options.model = model;
  if (max_tokens) options.maxTokens = max_tokens;
  if (temperature !== undefined) options.temperature = temperature;

  if (tools?.length > 0) {
    options.allowedTools = tools.map((t) => t.name);
  }

  if (thinking?.type === "enabled") {
    options.thinking = { type: "enabled", budgetTokens: thinking.budget_tokens || 10000 };
  }

  return options;
}

function sendSSE(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

app.listen(PORT, "0.0.0.0", () => {
  console.log(`SDK proxy listening on port ${PORT}`);
});
