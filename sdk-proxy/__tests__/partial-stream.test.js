import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createPartialStreamTracker } from "../partial-stream.js";

const delta = (d, extra = {}) => ({
  type: "stream_event",
  event: { type: "content_block_delta", index: 0, delta: d },
  ...extra,
});
const text = (t, extra) => delta({ type: "text_delta", text: t }, extra);
const assistant = (...blocks) => ({ type: "assistant", message: { content: blocks } });

// Mirrors the forwarding rules in server.js for the content channel.
async function forwardedContent(messages) {
  const partials = createPartialStreamTracker();
  const out = [];
  async function* fakeQuery() { yield* messages; }
  for await (const message of fakeQuery()) {
    if (message.type === "stream_event") {
      const d = partials.textDelta(message);
      if (d) out.push(d);
    } else if (message.type === "assistant") {
      for (const block of message.message.content) {
        if (block.type === "text" && block.text) {
          const unsent = partials.remainder(block.text);
          if (unsent) out.push(unsent);
        }
      }
    }
  }
  return out;
}

test("forwards each text delta and does not repeat the final message", async () => {
  const out = await forwardedContent([
    { type: "stream_event", event: { type: "message_start" } },
    text("Hel"), text("lo "), text("world"),
    assistant({ type: "text", text: "Hello world" }),
  ]);
  assert.deepEqual(out, ["Hel", "lo ", "world"]);
});

test("sends the whole message when nothing was streamed", async () => {
  const out = await forwardedContent([assistant({ type: "text", text: "Hello" })]);
  assert.deepEqual(out, ["Hello"]);
});

test("sends only the unstreamed tail when the final message is longer", async () => {
  const out = await forwardedContent([text("Hel"), assistant({ type: "text", text: "Hello" })]);
  assert.deepEqual(out, ["Hel", "lo"]);
});

test("does not leak thinking, tool input, or subagent deltas", async () => {
  const out = await forwardedContent([
    delta({ type: "thinking_delta", thinking: "secret" }),
    delta({ type: "input_json_delta", partial_json: '{"a":' }),
    text("sub text", { parent_tool_use_id: "toolu_1" }),
    { type: "stream_event", event: { type: "content_block_stop", index: 0 } },
    text("visible"),
    assistant({ type: "text", text: "visible" }),
  ]);
  assert.deepEqual(out, ["visible"]);
});

test("a new message resets the streamed text between assistant messages", async () => {
  const out = await forwardedContent([
    text("one"), assistant({ type: "text", text: "one" }),
    { type: "stream_event", event: { type: "message_start" } },
    text("two"), assistant({ type: "text", text: "two" }),
  ]);
  assert.deepEqual(out, ["one", "two"]);
});

test("server asks the SDK for partial messages", () => {
  const source = readFileSync(new URL("../server.js", import.meta.url), "utf8");
  assert.match(source, /includePartialMessages:\s*true/);
});
