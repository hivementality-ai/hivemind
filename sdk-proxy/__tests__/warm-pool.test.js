// The warm pool with the SDK replaced by a scripted fake. The fake behaves like
// query() in streaming-input mode: one process, many prompts, a "result"
// message closing each turn, and a process that exits when aborted.

import test from "node:test";
import assert from "node:assert/strict";
import { createWarmPool, configKey, splitDynamic, withTurnContext } from "../warm-pool.js";

const silent = { log() {}, error() {}, warn() {} };

function fakeSdk() {
  const spawned = [];
  const queryFn = ({ prompt, options }) => {
    const state = { options, aborted: false, mode: "ok" };
    const aborted = new Promise((resolve) => {
      options.abortController.signal.addEventListener("abort", () => {
        state.aborted = true;
        resolve();
      });
    });
    const gen = (async function* () {
      for await (const input of prompt) {
        if (state.mode === "crash") throw new Error("Claude Code process exited with code 1");
        if (state.mode === "hang") {
          await aborted;
          return;
        }
        yield { type: "assistant", message: { content: [{ type: "text", text: "hi" }] } };
        const isError = state.mode === "error";
        yield { type: "result", is_error: isError, result: `echo ${input.message.content}` };
      }
    })();
    gen.state = state;
    spawned.push(state);
    return gen;
  };
  return { queryFn, spawned };
}

function build({ maxWarm = 4, idleMs = 1000 } = {}) {
  const sdk = fakeSdk();
  const clock = { t: 0 };
  const pool = createWarmPool({ queryFn: sdk.queryFn, maxWarm, idleMs, now: () => clock.t, logger: silent });
  return { ...sdk, clock, pool };
}

async function drain(turn) {
  const messages = [];
  for await (const message of turn) messages.push(message);
  return messages;
}

async function runTurn(pool, sessionId, key, convoCount, prompt = "hello") {
  let entry = pool.checkout(sessionId, key, convoCount);
  const reused = Boolean(entry);
  if (!entry) entry = pool.create(sessionId, key, {});
  const messages = await drain(entry.turn(prompt));
  pool.release(entry, { ok: true, messageCount: convoCount + 1 });
  return { entry, reused, messages };
}

test("the second turn of a session reuses the live process", async () => {
  const { pool, spawned } = build();

  const first = await runTurn(pool, "s1", "k", 1, "one");
  const second = await runTurn(pool, "s1", "k", 3, "two");

  assert.equal(first.reused, false);
  assert.equal(second.reused, true);
  assert.equal(spawned.length, 1, "only one process was ever spawned");
  assert.equal(second.entry, first.entry);
  assert.equal(second.messages.at(-1).result, "echo two");
});

test("a config change replaces the warm process", async () => {
  const { pool, spawned } = build();

  const first = await runTurn(pool, "s1", configKey({ model: "a" }), 1);
  const second = await runTurn(pool, "s1", configKey({ model: "b" }), 3);

  assert.equal(second.reused, false);
  assert.equal(spawned.length, 2);
  assert.equal(spawned[0].aborted, true, "the stale process is shut down");
  assert.equal(first.entry.dead, true);
  assert.equal(pool.size(), 1);
});

test("configKey differs for any changed field and is stable otherwise", () => {
  const base = { model: "m", systemText: "s", tool_definitions: [{ name: "t" }] };
  assert.equal(configKey(base), configKey({ ...base }));
  assert.notEqual(configKey(base), configKey({ ...base, systemText: "s2" }));
  assert.notEqual(configKey(base), configKey({ ...base, tool_definitions: [{ name: "t2" }] }));
});

test("a history that does not line up with the process replaces it", async () => {
  const { pool, spawned } = build();

  await runTurn(pool, "s1", "k", 1);
  const second = await runTurn(pool, "s1", "k", 5);

  assert.equal(second.reused, false);
  assert.equal(spawned.length, 2);
  assert.equal(spawned[0].aborted, true);
});

test("an idle process is reaped after the idle window and not before", async () => {
  const { pool, spawned, clock } = build({ idleMs: 1000 });
  await runTurn(pool, "s1", "k", 1);

  clock.t = 999;
  assert.equal(pool.reap(), 0);
  assert.equal(pool.size(), 1);

  clock.t = 1000;
  assert.equal(pool.reap(), 1);
  assert.equal(pool.size(), 0);
  assert.equal(spawned[0].aborted, true);
  pool.closeAll();
});

test("the idle window counts from the end of the last turn", async () => {
  const { pool, clock } = build({ idleMs: 1000 });
  await runTurn(pool, "s1", "k", 1);
  clock.t = 900;
  await runTurn(pool, "s1", "k", 3);

  clock.t = 1500;
  assert.equal(pool.reap(), 0);
  clock.t = 1900;
  assert.equal(pool.reap(), 1);
});

test("a busy process is never reaped", async () => {
  const { pool, clock } = build({ idleMs: 1000 });
  const entry = pool.create("s1", "k", {});

  clock.t = 5000;
  assert.equal(pool.reap(), 0);
  assert.equal(entry.dead, false);
  pool.closeAll();
});

test("the cap evicts the least recently used idle process", async () => {
  const { pool, spawned } = build({ maxWarm: 2 });
  await runTurn(pool, "a", "k", 1);
  await runTurn(pool, "b", "k", 1);
  await runTurn(pool, "a", "k", 3); // a is now more recent than b

  await runTurn(pool, "c", "k", 1);

  assert.equal(pool.size(), 2);
  assert.equal(spawned[1].aborted, true, "b was the least recently used");
  assert.equal(spawned[0].aborted, false);
  assert.equal(pool.checkout("b", "k", 3), null);
  pool.closeAll();
});

test("when every slot is busy a new session is not warmed", () => {
  const { pool } = build({ maxWarm: 1 });
  pool.create("a", "k", {});

  assert.equal(pool.create("b", "k", {}), null);
  assert.equal(pool.size(), 1);
  pool.closeAll();
});

test("a second request for a busy session does not share its process", () => {
  const { pool } = build();
  pool.create("a", "k", {});

  assert.equal(pool.checkout("a", "k", 3), null);
  assert.equal(pool.create("a", "k", {}), null);
  pool.closeAll();
});

test("aborting a turn ends it quietly, stops the process and frees the slot", async () => {
  const { pool, spawned } = build();
  const entry = pool.create("s1", "k", {});
  spawned[0].mode = "hang";

  const running = drain(entry.turn("slow"));
  await new Promise((r) => setImmediate(r));
  entry.close();
  const messages = await running;
  pool.release(entry, { ok: false });

  assert.deepEqual(messages, []);
  assert.equal(spawned[0].aborted, true);
  assert.equal(pool.size(), 0);
  assert.equal(pool.checkout("s1", "k", 3), null);
});

test("a crashed process is discarded and the next turn starts fresh", async () => {
  const { pool, spawned } = build();
  await runTurn(pool, "s1", "k", 1);
  spawned[0].mode = "crash";

  const entry = pool.checkout("s1", "k", 3);
  await assert.rejects(drain(entry.turn("boom")), /exited with code 1/);
  pool.release(entry, { ok: false });

  assert.equal(pool.size(), 0);
  const next = await runTurn(pool, "s1", "k", 3);
  assert.equal(next.reused, false);
  assert.equal(spawned.length, 2);
  pool.closeAll();
});

test("a process that ends mid-turn without a result is reported and discarded", async () => {
  const { pool, spawned } = build();
  const entry = pool.create("s1", "k", {});
  spawned[0].options.abortController.abort(); // process exits on its own
  entry.input.end();

  await assert.rejects(drain(entry.turn("x")), /ended before the turn finished/);
  assert.equal(entry.dead, true);
  pool.release(entry, { ok: false });
  assert.equal(pool.size(), 0);
});

test("an error result abandoned by the caller closes the process", async () => {
  const { pool, spawned } = build();
  const entry = pool.create("s1", "k", {});
  spawned[0].mode = "error";

  for await (const message of entry.turn("x")) {
    if (message.type === "result") break;
  }
  pool.release(entry, { ok: false });

  assert.equal(spawned[0].aborted, true);
  assert.equal(pool.size(), 0);
});

test("a process that died while idle is never handed out again", async () => {
  const { pool, spawned } = build();
  const { entry } = await runTurn(pool, "s1", "k", 1);

  entry.close();

  assert.equal(pool.checkout("s1", "k", 3), null);
  assert.equal(pool.size(), 0);
  assert.equal(spawned.length, 1);
});

function open(pool, overrides = {}) {
  return pool.openTurn({
    sessionId: "s1", key: "k", messageCount: 1, prompt: "hi", options: {}, sink: { toolEvent: "a" },
    cold: () => ({ messages: null, warm: false, finish() {}, abort() {} }),
    ...overrides,
  });
}

test("openTurn reuses the process on the next turn and hands over the new sink", async () => {
  const { pool, spawned } = build();

  const first = open(pool);
  await drain(first.messages);
  first.finish(true);
  const second = open(pool, { messageCount: 3, sink: { toolEvent: "b" } });
  await drain(second.messages);
  second.finish(true);

  assert.equal(first.warm && second.warm, true);
  assert.equal(spawned.length, 1);
  assert.equal(pool.checkout("s1", "k", 5).sink.toolEvent, "b");
});

test("openTurn discards the process when the turn fails", async () => {
  const { pool } = build();
  const turn = open(pool);
  await drain(turn.messages);

  turn.finish(false);

  assert.equal(pool.size(), 0);
});

test("openTurn runs cold when no warm slot is free", () => {
  const { pool } = build({ maxWarm: 1 });
  open(pool, { sessionId: "busy" });

  const turn = open(pool, { sessionId: "other" });

  assert.equal(turn.warm, false);
  assert.equal(pool.size(), 1);
  pool.closeAll();
});

test("openTurn abort stops the process", () => {
  const { pool, spawned } = build();
  const turn = open(pool);

  turn.abort();

  assert.equal(spawned[0].aborted, true);
  turn.finish(false);
  assert.equal(pool.size(), 0);
});

test("closeAll shuts down every process", async () => {
  const { pool, spawned } = build();
  await runTurn(pool, "a", "k", 1);
  await runTurn(pool, "b", "k", 1);

  pool.closeAll();

  assert.equal(pool.size(), 0);
  assert.deepEqual(spawned.map((s) => s.aborted), [true, true]);
});

async function turnResult(turn) {
  const messages = await drain(turn.messages);
  turn.finish(true);
  return messages.at(-1).result;
}

test("a cold first turn sends the prompt alone", async () => {
  const { pool } = build();

  const result = await turnResult(open(pool, { prompt: "one", dynamicText: "ctx A" }));

  assert.equal(result, "echo one");
});

test("reuse with a changed dynamic block carries the new context in the prompt", async () => {
  const { pool, spawned } = build();
  await turnResult(open(pool, { prompt: "one", dynamicText: "ctx A" }));

  const second = open(pool, { prompt: "two", messageCount: 3, dynamicText: "ctx B" });
  const result = await turnResult(second);

  assert.equal(second.warm, true);
  assert.equal(spawned.length, 1);
  assert.equal(result, "echo <turn_context>\nctx B\n</turn_context>\n\ntwo");
});

test("reuse with an unchanged dynamic block sends the prompt alone", async () => {
  const { pool } = build();
  await turnResult(open(pool, { prompt: "one", dynamicText: "ctx A" }));

  const result = await turnResult(open(pool, { prompt: "two", messageCount: 3, dynamicText: "ctx A" }));

  assert.equal(result, "echo two");
});

test("the last seen context is tracked per turn, so returning to an old one re-sends it", async () => {
  const { pool } = build();
  await turnResult(open(pool, { prompt: "one", dynamicText: "ctx A" }));
  await turnResult(open(pool, { prompt: "two", messageCount: 3, dynamicText: "ctx B" }));

  const result = await turnResult(open(pool, { prompt: "three", messageCount: 5, dynamicText: "ctx A" }));

  assert.equal(result, "echo <turn_context>\nctx A\n</turn_context>\n\nthree");
});

test("reuse without any dynamic block sends the prompt alone", async () => {
  const { pool } = build();
  await turnResult(open(pool, { prompt: "one", dynamicText: "ctx A" }));

  const result = await turnResult(open(pool, { prompt: "two", messageCount: 3 }));

  assert.equal(result, "echo two");
});

test("splitDynamic separates a matching trailing block from the static text", () => {
  const blocks = [{ text: "core" }, { text: "rules" }, { text: "ctx" }];

  assert.deepEqual(splitDynamic(blocks, "ctx"), { staticText: "core\n\nrules", dynamicText: "ctx" });
});

test("splitDynamic declines when the last block differs, the text is empty, or the prompt is a string", () => {
  assert.equal(splitDynamic([{ text: "core" }, { text: "other" }], "ctx"), null);
  assert.equal(splitDynamic([{ text: "core" }], ""), null);
  assert.equal(splitDynamic("core ctx", "ctx"), null);
  assert.equal(splitDynamic([], "ctx"), null);
  assert.equal(splitDynamic([{ text: "core" }, {}], undefined), null);
});

test("withTurnContext wraps the context ahead of the prompt", () => {
  assert.equal(withTurnContext("hi", "ctx"), "<turn_context>\nctx\n</turn_context>\n\nhi");
});
