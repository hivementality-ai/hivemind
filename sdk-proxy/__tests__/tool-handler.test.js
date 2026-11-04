import test from "node:test";
import assert from "node:assert/strict";
import { makeToolHandler, toolTimeoutMs } from "../tool-handler.js";

const realFetch = globalThis.fetch;
const realTimeout = process.env.SDK_PROXY_TOOL_TIMEOUT_MS;

test.afterEach(() => {
  globalThis.fetch = realFetch;
  if (realTimeout === undefined) delete process.env.SDK_PROXY_TOOL_TIMEOUT_MS;
  else process.env.SDK_PROXY_TOOL_TIMEOUT_MS = realTimeout;
});

const handler = () => makeToolHandler({ name: "web_search", agentId: "a", sessionId: "s" });

const hangingFetch = (_url, { signal }) =>
  new Promise((_resolve, reject) => {
    signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
  });

test("returns the tool output on success", async () => {
  globalThis.fetch = async () => Response.json({ success: true, output: "ok" });
  const result = await handler()({ q: "x" });
  assert.deepEqual(result, { content: [{ type: "text", text: "ok" }] });
});

test("a hung Rails callback becomes a timeout error result", async () => {
  process.env.SDK_PROXY_TOOL_TIMEOUT_MS = "50";
  globalThis.fetch = hangingFetch;
  const result = await handler()({});
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /tool web_search timed out after \d+s/);
});

test("timeout message reports whole seconds", async () => {
  process.env.SDK_PROXY_TOOL_TIMEOUT_MS = "1000";
  globalThis.fetch = hangingFetch;
  const result = await handler()({});
  assert.match(result.content[0].text, /tool web_search timed out after 1s/);
});

test("non-2xx from Rails becomes an error result", async () => {
  globalThis.fetch = async () => new Response("boom", { status: 500 });
  const result = await handler()({});
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /500.*boom/);
});

test("connection refusal becomes an error result", async () => {
  globalThis.fetch = async () => {
    throw new TypeError("fetch failed");
  };
  const result = await handler()({});
  assert.equal(result.isError, true);
  assert.match(result.content[0].text, /fetch failed/);
});

test("emits a failed tool_result event on timeout", async () => {
  process.env.SDK_PROXY_TOOL_TIMEOUT_MS = "20";
  globalThis.fetch = hangingFetch;
  const events = [];
  const h = makeToolHandler({
    name: "t",
    agentId: "a",
    sessionId: "s",
    onToolEvent: (type, data) => events.push([type, data]),
  });
  await h({});
  assert.equal(events[1][0], "tool_result");
  assert.equal(events[1][1].success, false);
});

test("default timeout exceeds the longest Rails-side tool timeout", () => {
  delete process.env.SDK_PROXY_TOOL_TIMEOUT_MS;
  assert.ok(toolTimeoutMs() > 1_800_000);
});
