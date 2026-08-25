import test from "node:test";
import assert from "node:assert/strict";
import { Semaphore, LoadShedError } from "../concurrency.js";

test("never runs more than maxConcurrent at once", async () => {
  const sem = new Semaphore({ maxConcurrent: 4, maxQueue: 100 });
  let running = 0;
  let peak = 0;

  const work = async () => {
    const release = await sem.acquire();
    running += 1;
    peak = Math.max(peak, running);
    await new Promise((r) => setImmediate(r));
    running -= 1;
    release();
  };

  await Promise.all(Array.from({ length: 50 }, work));
  assert.equal(peak, 4, `peak concurrency was ${peak}`);
  assert.equal(sem.stats().inflight, 0);
  assert.equal(sem.stats().total_acquired, 50);
});

test("sheds with 429 instead of spawning without limit", async () => {
  const sem = new Semaphore({ maxConcurrent: 1, maxQueue: 1 });
  const held = await sem.acquire();
  const queued = sem.acquire(); // fills the single queue slot

  await assert.rejects(() => sem.acquire(), (err) => {
    assert.ok(err instanceof LoadShedError);
    assert.equal(err.status, 429);
    assert.equal(err.reason, "load_shed");
    assert.equal(err.retryable, true);
    return true;
  });

  assert.equal(sem.stats().total_shed, 1);
  held();
  (await queued)();
});

test("queued callers run as slots free up, in order", async () => {
  const sem = new Semaphore({ maxConcurrent: 1, maxQueue: 10 });
  const order = [];
  const first = await sem.acquire();

  const rest = [1, 2, 3].map((n) =>
    sem.acquire().then((release) => { order.push(n); release(); }),
  );

  first();
  await Promise.all(rest);
  assert.deepEqual(order, [1, 2, 3]);
});

test("double release does not hand out a phantom slot", async () => {
  const sem = new Semaphore({ maxConcurrent: 1, maxQueue: 5 });
  const release = await sem.acquire();
  release();
  release();
  assert.equal(sem.stats().inflight, 0);

  const a = await sem.acquire();
  await assert.rejects(() => Promise.all([sem.acquire(), sem.acquire(), sem.acquire(),
    sem.acquire(), sem.acquire(), sem.acquire()]));
  a();
});

test("rejects nonsense ceilings at construction", () => {
  assert.throws(() => new Semaphore({ maxConcurrent: 0, maxQueue: 1 }), TypeError);
  assert.throws(() => new Semaphore({ maxConcurrent: 1, maxQueue: -1 }), TypeError);
});
