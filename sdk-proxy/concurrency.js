// Bounded work queue for outbound provider work.
//
// The OAuth path spawns a fresh Claude Code subprocess per request, and each
// subprocess opens its own TCP connections with its own internal retry ladder.
// Unbounded, N in-flight requests become N * (retries) sockets against a
// host-wide pool of ~16k ephemeral ports that every stack on the box shares.
//
// So the ceiling is not a nicety: it is this stack's declared share of a
// finite host resource. Keep sum(SDK_PROXY_MAX_CONCURRENCY) across all stacks
// well under host capacity. See MULTI-STACK.md.

export class LoadShedError extends Error {
  constructor(message, { retryAfterMs = 5000 } = {}) {
    super(message);
    this.name = "LoadShedError";
    this.status = 429;
    this.reason = "load_shed";
    this.retryable = true;
    this.retryAfterMs = retryAfterMs;
  }
}

export class Semaphore {
  /**
   * @param {object} opts
   * @param {number} opts.maxConcurrent  slots that may run at once
   * @param {number} opts.maxQueue       callers that may wait for a slot;
   *                                     beyond this we shed with 429 rather
   *                                     than let the backlog grow unbounded
   */
  constructor({ maxConcurrent, maxQueue }) {
    if (!Number.isInteger(maxConcurrent) || maxConcurrent < 1) {
      throw new TypeError("maxConcurrent must be a positive integer");
    }
    if (!Number.isInteger(maxQueue) || maxQueue < 0) {
      throw new TypeError("maxQueue must be a non-negative integer");
    }
    this.maxConcurrent = maxConcurrent;
    this.maxQueue = maxQueue;
    this.inflight = 0;
    this.waiters = [];
    this.totalShed = 0;
    this.totalAcquired = 0;
  }

  /**
   * @returns {Promise<() => void>} resolves with a release function. Callers
   *   MUST release in a finally block.
   * @throws {LoadShedError} when the queue is already full.
   */
  acquire() {
    if (this.inflight < this.maxConcurrent) {
      this.inflight += 1;
      this.totalAcquired += 1;
      return Promise.resolve(this.#makeRelease());
    }

    if (this.waiters.length >= this.maxQueue) {
      this.totalShed += 1;
      return Promise.reject(
        new LoadShedError(
          `sdk-proxy at capacity (${this.maxConcurrent} in flight, ${this.waiters.length} queued)`,
        ),
      );
    }

    return new Promise((resolve) => {
      this.waiters.push(() => {
        this.inflight += 1;
        this.totalAcquired += 1;
        resolve(this.#makeRelease());
      });
    });
  }

  #makeRelease() {
    let released = false;
    return () => {
      if (released) return; // idempotent: double-release must not free a slot twice
      released = true;
      this.inflight -= 1;
      const next = this.waiters.shift();
      if (next) next();
    };
  }

  stats() {
    return {
      inflight: this.inflight,
      queued: this.waiters.length,
      max_concurrent: this.maxConcurrent,
      max_queue: this.maxQueue,
      total_acquired: this.totalAcquired,
      total_shed: this.totalShed,
    };
  }
}
