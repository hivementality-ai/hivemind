// Fault-injection tests for the full outbound pipeline.
//
// Replays the 2026-08-24 incident in miniature: a provider stubbed to return
// `400 "You're out of extra usage"` for every call, driven under load. The
// assertion that matters is the one the incident failed — that the number of
// attempts that actually reach the network is bounded and countable, rather
// than growing with the duration of the outage.

import test from "node:test";
import assert from "node:assert/strict";
import { createGuard } from "../guard.js";

const silent = { error() {}, warn() {}, log() {} };

const quotaError = () =>
  Object.assign(
    new Error("You're out of extra usage. Add more at claude.ai/settings/usage and keep going."),
    { status: 400 },
  );

test("a permanently failing credential stops reaching the network", async () => {
  let attempts = 0;
  const guard = createGuard({
    maxConcurrent: 4, maxQueue: 64, failureThreshold: 3, openMs: 60_000, logger: silent,
  });

  const results = { refused: 0, attempted: 0 };
  for (let i = 0; i < 500; i++) {
    try {
      await guard.run({
        credential: "cred",
        invoke: async () => { attempts += 1; throw quotaError(); },
      });
    } catch (err) {
      if (err.name === "CircuitOpenError") results.refused += 1;
      else results.attempted += 1;
    }
  }

  assert.equal(attempts, 3, "only the pre-threshold attempts open a socket");
  assert.equal(results.attempted, 3);
  assert.equal(results.refused, 497, "everything after the circuit opens fails fast, locally");
  assert.equal(guard.breaker.state("cred"), "open");
});

test("the failure is visible rather than silent", async () => {
  const logged = [];
  const guard = createGuard({
    maxConcurrent: 2, maxQueue: 8, failureThreshold: 1, openMs: 60_000,
    logger: { error: (m) => logged.push(m) },
  });

  await assert.rejects(() =>
    guard.run({ credential: "cred", invoke: async () => { throw quotaError(); } }));

  assert.equal(logged.filter((m) => m.includes("[ALARM]")).length, 1);
  assert.match(logged[0], /circuit OPEN/);
  assert.match(logged[0], /quota_exhausted/);

  const health = guard.health();
  assert.equal(health.degraded, true);
  assert.equal(health.reason, "provider circuit open: quota_exhausted");
  assert.equal(health.circuits[0].reason, "quota_exhausted");
});

test("concurrency stays capped even under a 500-request stampede", async () => {
  let running = 0;
  let peak = 0;
  const guard = createGuard({
    maxConcurrent: 4, maxQueue: 1000, failureThreshold: 100, openMs: 60_000, logger: silent,
  });

  await Promise.all(Array.from({ length: 500 }, () =>
    guard.run({
      credential: "cred",
      invoke: async () => {
        running += 1;
        peak = Math.max(peak, running);
        await new Promise((r) => setImmediate(r));
        running -= 1;
      },
    })));

  assert.equal(peak, 4, `peak in-flight was ${peak}, ceiling is 4`);
  assert.equal(guard.health().concurrency.inflight, 0);
});

test("overflow is shed with 429, not spawned", async () => {
  const guard = createGuard({
    maxConcurrent: 1, maxQueue: 2, failureThreshold: 100, openMs: 60_000, logger: silent,
  });
  let spawned = 0;
  const slow = () => guard.run({
    credential: "cred",
    invoke: async () => { spawned += 1; await new Promise((r) => setTimeout(r, 20)); },
  });

  const outcomes = await Promise.allSettled([slow(), slow(), slow(), slow(), slow()]);
  const shed = outcomes.filter((o) => o.status === "rejected" && o.reason.name === "LoadShedError");

  assert.equal(shed.length, 2, "two over the 1+2 ceiling are shed");
  assert.equal(shed[0].reason.status, 429);
  assert.equal(spawned, 3, "only the admitted requests ever spawn work");
});

test("an open circuit does not consume a concurrency slot", async () => {
  const guard = createGuard({
    maxConcurrent: 1, maxQueue: 0, failureThreshold: 1, openMs: 60_000, logger: silent,
  });
  await assert.rejects(() =>
    guard.run({ credential: "broke", invoke: async () => { throw quotaError(); } }));

  // With the circuit open, a refused call must leave the slot free for a
  // healthy credential — one dead account cannot wedge the queue.
  await assert.rejects(() => guard.run({ credential: "broke", invoke: async () => {} }),
    (err) => err.name === "CircuitOpenError");
  assert.equal(guard.health().concurrency.inflight, 0);

  await guard.run({ credential: "healthy", invoke: async () => "served" });
});

// Superseded 2026-09-08: this asserted all 100 transient failures reach the
// network. An unbroken run of them is an outage, and letting it dial 100 times
// is how the host's ephemeral port pool disappears. Transient failures still
// flow freely below the backstop; the run is what is now bounded.
test("transient failures keep flowing until the backstop stops the run", async () => {
  let attempts = 0;
  const guard = createGuard({
    maxConcurrent: 4, maxQueue: 64, failureThreshold: 3, anyFailureThreshold: 25,
    openMs: 60_000, logger: silent,
  });

  for (let i = 0; i < 100; i++) {
    await assert.rejects(() => guard.run({
      credential: "cred",
      invoke: async () => { attempts += 1; throw Object.assign(new Error("overloaded"), { status: 529 }); },
    }));
  }

  assert.equal(attempts, 25, "the run is bounded: 75 of the 100 opened no socket at all");
  assert.equal(guard.breaker.state("cred"), "open");
});

test("a transient blip broken by a success never trips the backstop", async () => {
  const guard = createGuard({
    maxConcurrent: 4, maxQueue: 64, failureThreshold: 3, anyFailureThreshold: 5,
    openMs: 60_000, logger: silent,
  });

  for (let round = 0; round < 10; round += 1) {
    for (let i = 0; i < 4; i += 1) {
      await assert.rejects(() => guard.run({
        credential: "cred",
        invoke: async () => { throw Object.assign(new Error("overloaded"), { status: 529 }); },
      }));
    }
    await guard.run({ credential: "cred", invoke: async () => "served" });
  }

  assert.equal(guard.breaker.state("cred"), "closed");
});

// The failure that actually hit 192.168.1.5 on 2026-09-08: the Claude Code
// subprocess reports port exhaustion as a plain connection error, and nothing
// upstream can tell it apart from a blip.
test("an endless run of `Connection error` stops dialling and alarms", async () => {
  const lines = [];
  let attempts = 0;
  const guard = createGuard({
    maxConcurrent: 4, maxQueue: 64, failureThreshold: 3, anyFailureThreshold: 10,
    openMs: 60_000, logger: { error: (l) => lines.push(l) },
  });

  for (let i = 0; i < 200; i++) {
    await assert.rejects(() => guard.run({
      credential: "cred",
      invoke: async () => {
        attempts += 1;
        throw new Error("API Error: Connection error. (Claude Code process exited with code 1)");
      },
    }));
  }

  assert.equal(attempts, 10, "190 of 200 calls opened no socket");
  assert.equal(guard.breaker.state("cred"), "open");
  assert.equal(lines.filter((l) => l.includes("[ALARM]")).length, 1, "exactly one alarm, on the transition");
});

test("recovers after a human tops the account up", async () => {
  const guard = createGuard({
    maxConcurrent: 2, maxQueue: 8, failureThreshold: 1, openMs: 60_000, logger: silent,
  });
  await assert.rejects(() =>
    guard.run({ credential: "cred", invoke: async () => { throw quotaError(); } }));
  await assert.rejects(() => guard.run({ credential: "cred", invoke: async () => "ok" }));

  guard.breaker.reset("cred"); // what POST /admin/circuit/reset does

  assert.equal(await guard.run({ credential: "cred", invoke: async () => "ok" }), "ok");
  assert.equal(guard.health().degraded, false);
});

test("the OAuth 'exited with code 1' shape still opens the circuit", async () => {
  const guard = createGuard({
    maxConcurrent: 2, maxQueue: 8, failureThreshold: 2, openMs: 60_000, logger: silent,
  });
  const stderr = 'API Error: 400 {"error":{"message":"You\'re out of extra usage."}}';

  for (let i = 0; i < 2; i++) {
    await assert.rejects(() => guard.run({
      credential: "cred",
      stderr: () => stderr,
      invoke: async () => { throw new Error("Claude Code process exited with code 1"); },
    }));
  }

  assert.equal(guard.breaker.state("cred"), "open");
  assert.equal(guard.health().circuits[0].reason, "quota_exhausted");
});
