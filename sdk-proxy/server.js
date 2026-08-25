import express from "express";
import Anthropic from "@anthropic-ai/sdk";
import { query } from "@anthropic-ai/claude-agent-sdk";
import { buildMcpServer } from "./mcp-tool-bridge.js";
import { existsSync, mkdirSync } from "fs";
import { classifyError, toErrorBody } from "./error-classifier.js";
import { credentialKey } from "./circuit-breaker.js";
import { createGuard } from "./guard.js";

const app = express();
app.use(express.json({ limit: "10mb" }));

const PORT = process.env.PORT || 3003;

const intEnv = (name, fallback) => {
  const parsed = Number.parseInt(process.env[name] ?? "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
};

// ─── Resource discipline ──────────────────────────────────────────────
// Every in-flight OAuth request spawns a Claude Code subprocess that opens
// its own TCP connections. On macOS, container egress consumes the *host's*
// ~16k ephemeral port pool, shared by every stack on the box. These ceilings
// are this stack's declared share of that pool — see MULTI-STACK.md.
const MAX_CONCURRENCY = Math.max(1, intEnv("SDK_PROXY_MAX_CONCURRENCY", 4));
const MAX_QUEUE = intEnv("SDK_PROXY_MAX_QUEUE", 16);
const CIRCUIT_FAILURE_THRESHOLD = Math.max(1, intEnv("SDK_PROXY_CIRCUIT_THRESHOLD", 3));
const CIRCUIT_OPEN_MS = Math.max(1000, intEnv("SDK_PROXY_CIRCUIT_OPEN_MS", 15 * 60 * 1000));
const STDERR_CAPTURE_BYTES = 16 * 1024;

const guard = createGuard({
  maxConcurrent: MAX_CONCURRENCY,
  maxQueue: MAX_QUEUE,
  failureThreshold: CIRCUIT_FAILURE_THRESHOLD,
  openMs: CIRCUIT_OPEN_MS,
});

// query() adds an exit listener per subprocess; the semaphore is the real
// bound, this just keeps the ceiling above it so no spurious warning fires.
process.setMaxListeners(MAX_CONCURRENCY + 20);

// Health check. Reports liveness (200 whenever the HTTP server answers) plus
// the two things that were invisible during the 40-hour silent outage: the
// per-credential circuit state and how much outbound work is in flight.
app.get("/health", (_req, res) => {
  res.json(guard.health());
});

// Clear a credential's circuit — called by Rails when a human updates the
// token or tops the account up, so recovery does not wait out the cooldown.
app.post("/admin/circuit/reset", (req, res) => {
  const secret = process.env.INTERNAL_API_SECRET;
  if (secret && req.headers["x-internal-secret"] !== secret) {
    return res.status(403).json({ error: "forbidden" });
  }
  const token = req.body?.token;
  guard.breaker.reset(token ? credentialKey(token) : null);
  console.log(`[circuit] reset ${token ? credentialKey(token) : "ALL"}`);
  res.json({ ok: true, circuits: guard.breaker.snapshot() });
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
    effort,
  } = req.body;

  const isOAuth = token.startsWith("sk-ant-oat");
  const credential = credentialKey(token);
  console.log(`[chat] cred=${credential} isOAuth=${isOAuth} stream=${stream} tools=${tool_definitions?.length || 0} agent=${agent_id} session=${session_id}`);

  try {
    await guard.run({
      credential,
      invoke: async () => {
        if (isOAuth) {
          return handleOAuth(req, res, token, { messages, tools, model, max_tokens, temperature, thinking, systemPrompt, stream, agent_id, session_id, tool_definitions });
        }
        const client = new Anthropic({ apiKey: token });
        const params = buildApiParams({ messages, tools, model, max_tokens, temperature, thinking, systemPrompt, effort });
        return stream ? handleApiStream(res, client, params) : handleApiSync(res, client, params);
      },
    });
  } catch (err) {
    respondWithError(res, err, credential);
  }
});

// ─── Error handling ───

// guard.run has already classified and recorded the failure; this only turns
// the verdict into a response the Rails side can act on without string-matching.
function respondWithError(res, err, credential) {
  const info = err.classification || classifyError(err, { stderr: err.subprocessStderr });
  console.error(
    `[error] cred=${credential} reason=${info.reason} ` +
    `retryable=${info.retryable} status=${info.status}: ${info.message}`,
  );

  if (res.headersSent) {
    // Stream already open — the SSE error frame carried the verdict.
    if (!res.writableEnded) res.end();
    return;
  }

  if (info.retryAfterMs != null) res.set("Retry-After", String(Math.ceil(info.retryAfterMs / 1000)));
  res.status(info.status).json(toErrorBody(info));
}

// ─── OAuth path: Claude Code via Agent SDK ───

// The Agent SDK surfaces every failure as `Claude Code process exited with
// code 1`, which erases the underlying HTTP status — a quota 400 and a
// transient socket error look identical. The subprocess does print the real
// cause on stderr, so capture it and attach it to the thrown error before it
// reaches the classifier.
async function handleOAuth(_req, res, token, params) {
  const stderrCapture = { text: "" };
  try {
    return await runOAuth(res, token, params, stderrCapture);
  } catch (err) {
    if (stderrCapture.text && !err.subprocessStderr) {
      err.subprocessStderr = stderrCapture.text;
    }
    throw err;
  }
}

async function runOAuth(res, token, params, stderrCapture) {
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
  options.stderr = (data) => {
    const text = String(data);
    console.error(`[claude-code stderr] ${text}`);
    // Ring-capped so a chatty subprocess cannot grow this without bound.
    if (stderrCapture.text.length < STDERR_CAPTURE_BYTES) {
      stderrCapture.text = (stderrCapture.text + text).slice(-STDERR_CAPTURE_BYTES);
    }
  };

  // Log what's being sent to the SDK for debugging
  const systemLines = (systemText || "").split("\n").length;
  const historyMsgs = conversationMessages.length - 1;
  console.log(`[oauth-prompt] agent=${agent_id} session=${session_id} model=${model}`);
  console.log(`[oauth-prompt] systemPrompt: ${systemLines} lines (${(systemText || "").length} chars)`);
  console.log(`[oauth-prompt] conversation history: ${historyMsgs} messages included`);
  console.log(`[oauth-prompt] user prompt: "${prompt.substring(0, 200)}${prompt.length > 200 ? "..." : ""}"`);
  console.log(`[oauth-prompt] tools: ${tool_definitions?.length || 0} MCP tools`);

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

    // Claude Code surfaces upstream drops as a result with is_error/"API Error:
    // Connection error." Those are transient, so retry the whole turn — but ONLY
    // while nothing has been streamed to the client yet. Once any content, tool,
    // or thinking event has gone out, re-running would duplicate output (and
    // re-fire side-effecting tools), so we surface the error instead.
    const MAX_ATTEMPTS = 3;
    let producedOutput = false;
    let lastError = null;
    let classification = null;

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const activeTools = new Set();
      let isThinking = false;
      let errored = false;
      // Snapshot listeners before query() so we can clean up after
      const listenersBefore = process.listeners("exit").length;
      try {
        for await (const message of query({ prompt, options })) {
          console.log(`[query] message type=${message.type}`, JSON.stringify(message).substring(0, 300));

          if (message.type === "text") {
            if (isThinking) { sendSSE(res, "thinking_stop", {}); isThinking = false; }
            producedOutput = true;
            sendSSE(res, "content", { content: message.text });
          } else if (message.type === "thinking") {
            if (!isThinking) { sendSSE(res, "thinking_start", {}); isThinking = true; }
            producedOutput = true;
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
                producedOutput = true;
                sendSSE(res, "content", { content: block.text });
              } else if (block.type === "thinking" && block.thinking) {
                if (!isThinking) { sendSSE(res, "thinking_start", {}); isThinking = true; }
                producedOutput = true;
                sendSSE(res, "thinking", { thinking: block.thinking });
              } else if (block.type === "tool_use") {
                // MCP tools are handled by the bridge callbacks — only emit
                // tool_start here for Claude Code's own built-in tools
                if (!mcpToolNames.has(block.name)) {
                  producedOutput = true;
                  sendSSE(res, "tool_start", { tool: block.name, input: block.input || {} });
                  activeTools.add(block.name);
                }
              }
            }
          } else if (message.type === "tool_progress") {
            if (isThinking) { sendSSE(res, "thinking_stop", {}); isThinking = false; }
            // Claude Code's own tool is actively running
            if (!activeTools.has(message.tool_name)) {
              producedOutput = true;
              sendSSE(res, "tool_start", { tool: message.tool_name, input: {} });
              activeTools.add(message.tool_name);
            }
          } else if (message.type === "result") {
            if (isThinking) { sendSSE(res, "thinking_stop", {}); isThinking = false; }
            const isErr = message.is_error === true ||
              (typeof message.subtype === "string" && message.subtype.startsWith("error"));
            if (isErr) {
              // Don't emit result yet — let the retry logic below decide.
              errored = true;
              lastError = message.result || message.subtype || "API Error";
              break;
            }
            // Close any remaining active tools
            for (const toolName of activeTools) {
              sendSSE(res, "tool_result", { tool: toolName, output: "", success: true });
            }
            activeTools.clear();
            const usage = message.usage || {};
            sendSSE(res, "result", { content: message.result, usage });
          }
        }
      } catch (err) {
        errored = true;
        lastError = err.message;
      } finally {
        // Clean up exit listeners added by query() subprocess
        const listenersAfter = process.listeners("exit");
        if (listenersAfter.length > listenersBefore) {
          const toRemove = listenersAfter.slice(listenersBefore);
          toRemove.forEach(fn => process.removeListener("exit", fn));
        }
      }

      if (!errored) break;

      // Classify BEFORE deciding to retry. Retrying a permanent failure is
      // exactly what consumed the host's port pool: a quota 400 will fail
      // identically on every attempt, and retrying local port exhaustion
      // makes the exhaustion worse.
      classification = classifyError(
        lastError instanceof Error ? lastError : new Error(String(lastError || "API Error")),
        { stderr: stderrCapture.text },
      );

      const canRetry = classification.retryable && !producedOutput && attempt < MAX_ATTEMPTS;
      if (canRetry) {
        const backoffMs = 1000 * attempt;
        console.warn(`[oauth] attempt ${attempt}/${MAX_ATTEMPTS} failed before any output (${lastError}); retrying in ${backoffMs}ms`);
        await new Promise((r) => setTimeout(r, backoffMs));
        continue;
      }

      // Permanent, out of retries, or output already streamed — surface as an
      // error so Hivemind shows a failure and lets the user retry, rather than
      // silently persisting "API Error: Connection error." as the reply.
      console.error(`[oauth] giving up after attempt ${attempt} (producedOutput=${producedOutput}, retryable=${classification.retryable}): ${lastError}`);
      // Headers are already flushed, so the verdict has to travel as an SSE
      // frame rather than an HTTP status.
      sendSSE(res, "error", toErrorBody(classification));
      break;
    }

    sendSSE(res, "done", {});
    res.end();

    // Rethrow after closing the stream cleanly, so the credential's circuit
    // still records the failure. respondWithError sees headersSent and stops.
    if (classification && !classification.retryable) {
      throw errorFromClassification(classification);
    }
  } else {
    // Non-streaming: nothing is sent until the turn finishes, so we can safely
    // retry a transient connection error (is_error result) up to MAX_ATTEMPTS.
    const MAX_ATTEMPTS = 3;
    let fullContent = "";
    let usage = {};
    let lastError = null;

    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      fullContent = "";
      let errored = false;
      const listenersBefore = process.listeners("exit").length;

      try {
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
            const isErr = message.is_error === true ||
              (typeof message.subtype === "string" && message.subtype.startsWith("error"));
            if (isErr) {
              errored = true;
              lastError = message.result || message.subtype || "API Error";
            } else {
              fullContent = message.result || fullContent;
            }
            if (message.usage) usage = message.usage;
          }
        }
      } catch (err) {
        errored = true;
        lastError = err.message;
      } finally {
        // Clean up exit listeners added by query() subprocess
        const listenersAfter = process.listeners("exit");
        if (listenersAfter.length > listenersBefore) {
          const toRemove = listenersAfter.slice(listenersBefore);
          toRemove.forEach(fn => process.removeListener("exit", fn));
        }
      }

      if (!errored) {
        return res.json({ content: fullContent || null, thinking: null, tool_calls: null, usage });
      }

      const classification = classifyError(
        lastError instanceof Error ? lastError : new Error(String(lastError || "API Error")),
        { stderr: stderrCapture.text },
      );

      if (classification.retryable && attempt < MAX_ATTEMPTS) {
        const backoffMs = 1000 * attempt;
        console.warn(`[oauth-sync] attempt ${attempt}/${MAX_ATTEMPTS} failed (${lastError}); retrying in ${backoffMs}ms`);
        await new Promise((r) => setTimeout(r, backoffMs));
        continue;
      }

      console.error(`[oauth-sync] giving up after ${attempt} attempts (retryable=${classification.retryable}): ${lastError}`);
      // Thrown, not returned: guard.run must see the failure to record it
      // against this credential's circuit. respondWithError renders it.
      throw errorFromClassification(classification);
    }
  }
}

// Rebuild an Error carrying an already-settled verdict, so the classifier
// honours it verbatim instead of re-deriving one from the message text.
function errorFromClassification(classification) {
  const err = new Error(classification.message);
  err.status = classification.status;
  err.reason = classification.reason;
  err.retryable = classification.retryable;
  err.classification = classification;
  return err;
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

function buildApiParams({ messages, tools, model, max_tokens, temperature, thinking, systemPrompt, effort }) {
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

  // Reasoning effort. Hivemind gates this to models that support it, so it's
  // safe to forward as output_config.effort here.
  if (effort) params.output_config = { ...(params.output_config || {}), effort };

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
