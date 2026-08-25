// Per-credential circuit breaker.
//
// When a credential has failed permanently N times in a row (out of credit,
// revoked token, forbidden), the only correct behaviour is to stop dialling
// entirely until a human intervenes. While the circuit is open we fail fast
// in-process: zero sockets, zero subprocesses, zero ephemeral ports consumed.
//
// Keyed per credential rather than per process so one exhausted account does
// not silence a second, healthy account served by the same proxy.

import { createHash } from "crypto";

export class CircuitOpenError extends Error {
  constructor(reason, openedAt, retryAfterMs) {
    super(`provider circuit open: ${reason}`);
    this.name = "CircuitOpenError";
    this.status = 503;
    this.reason = reason;
    this.retryable = false;
    this.circuitOpenedAt = openedAt;
    this.retryAfterMs = retryAfterMs;
  }
}

/** Stable, non-reversible label for a credential — never log the token. */
export function credentialKey(token) {
  return createHash("sha256").update(String(token)).digest("hex").slice(0, 12);
}

export class CircuitBreaker {
  /**
   * @param {object} opts
   * @param {number} opts.failureThreshold consecutive permanent failures before opening
   * @param {number} opts.openMs           how long to stay open before probing
   * @param {() => number} [opts.now]      injectable clock for tests
   */
  constructor({ failureThreshold = 3, openMs = 15 * 60 * 1000, now = Date.now } = {}) {
    this.failureThreshold = failureThreshold;
    this.openMs = openMs;
    this.now = now;
    /** @type {Map<string, {failures: number, state: string, reason: string|null, openedAt: number|null, lastMessage: string|null}>} */
    this.circuits = new Map();
  }

  #entry(key) {
    let entry = this.circuits.get(key);
    if (!entry) {
      entry = { failures: 0, state: "closed", reason: null, openedAt: null, lastMessage: null };
      this.circuits.set(key, entry);
    }
    return entry;
  }

  /**
   * Current state, transitioning open -> half_open once the cooldown elapses.
   * @returns {"closed"|"open"|"half_open"}
   */
  state(key) {
    const entry = this.circuits.get(key);
    if (!entry || entry.state === "closed") return "closed";
    if (entry.state === "open" && this.now() - entry.openedAt >= this.openMs) {
      entry.state = "half_open";
    }
    return entry.state;
  }

  /**
   * Gate a call. Half-open lets exactly one probe through per cooldown window.
   * @throws {CircuitOpenError}
   */
  check(key) {
    const state = this.state(key);
    if (state !== "open") return;
    const entry = this.#entry(key);
    const retryAfterMs = Math.max(0, entry.openedAt + this.openMs - this.now());
    throw new CircuitOpenError(entry.reason || "provider_unavailable", entry.openedAt, retryAfterMs);
  }

  recordSuccess(key) {
    const entry = this.#entry(key);
    entry.failures = 0;
    entry.state = "closed";
    entry.reason = null;
    entry.openedAt = null;
    entry.lastMessage = null;
  }

  /**
   * Count one permanent failure. Opens the circuit at the threshold, and
   * re-opens immediately if we were half-open (the probe failed).
   */
  recordPermanentFailure(key, reason, message = null) {
    const entry = this.#entry(key);
    entry.failures += 1;
    entry.reason = reason;
    entry.lastMessage = message;

    if (entry.state === "half_open" || entry.failures >= this.failureThreshold) {
      entry.state = "open";
      entry.openedAt = this.now();
    }
    return entry.state;
  }

  /** Transient failures never open the circuit, but do clear a half-open probe. */
  recordTransientFailure(key) {
    const entry = this.#entry(key);
    if (entry.state === "half_open") {
      entry.state = "open";
      entry.openedAt = this.now();
    }
  }

  /** Human updated the credential — resume immediately. */
  reset(key) {
    if (key) this.circuits.delete(key);
    else this.circuits.clear();
  }

  /** True if any credential is currently not serving. */
  anyOpen() {
    for (const key of this.circuits.keys()) {
      if (this.state(key) !== "closed") return true;
    }
    return false;
  }

  snapshot() {
    return [...this.circuits.entries()].map(([key, entry]) => ({
      credential: key,
      state: this.state(key),
      reason: entry.reason,
      consecutive_failures: entry.failures,
      opened_at: entry.openedAt ? new Date(entry.openedAt).toISOString() : null,
      last_message: entry.lastMessage,
    }));
  }
}
