// The resource-discipline pipeline every outbound provider call goes through.
//
// Order is deliberate and load-bearing:
//
//   1. circuit    — an open circuit must not open a socket, spawn a
//                   subprocess, or even occupy a concurrency slot.
//   2. semaphore  — bound how many calls may be in flight; shed the rest.
//   3. invoke     — the actual provider call.
//   4. record     — classify the outcome and update the credential's circuit.
//
// Kept out of server.js so the whole pipeline can be driven under fault
// injection in tests without an HTTP server or a real subprocess.

import { classifyError, opensCircuit } from "./error-classifier.js";
import { Semaphore } from "./concurrency.js";
import { CircuitBreaker } from "./circuit-breaker.js";

export function createGuard({
  maxConcurrent,
  maxQueue,
  failureThreshold,
  openMs,
  now,
  logger = console,
} = {}) {
  const semaphore = new Semaphore({ maxConcurrent, maxQueue });
  const breaker = new CircuitBreaker({ failureThreshold, openMs, now });

  /**
   * @param {object} opts
   * @param {string} opts.credential  hashed credential key
   * @param {() => Promise<any>} opts.invoke  the provider call
   * @param {() => string} [opts.stderr]  captured subprocess stderr, read lazily
   * @returns {Promise<any>} whatever invoke resolves to
   * @throws the original error, annotated with `.classification`
   */
  async function run({ credential, invoke, stderr }) {
    breaker.check(credential); // throws CircuitOpenError — no socket, no slot

    const release = await semaphore.acquire(); // throws LoadShedError at capacity
    try {
      const result = await invoke();
      breaker.recordSuccess(credential);
      return result;
    } catch (err) {
      err.classification = record(credential, err, stderr ? stderr() : err.subprocessStderr);
      throw err;
    } finally {
      release();
    }
  }

  function record(credential, err, stderrText) {
    const classification = classifyError(err, { stderr: stderrText });

    if (classification.retryable) {
      breaker.recordTransientFailure(credential);
      return classification;
    }

    const state = breaker.recordPermanentFailure(
      credential,
      classification.reason,
      classification.message,
    );

    if (opensCircuit(classification) && state === "open") {
      // The single log line that would have caught the 40-hour outage on day one.
      logger.error(
        `[ALARM] provider circuit OPEN cred=${credential} reason=${classification.reason} ` +
        `— refusing all outbound calls for this credential until a human acts. ` +
        `${classification.message}`,
      );
    }
    return classification;
  }

  function health() {
    const circuits = breaker.snapshot();
    const openCircuit = circuits.find((c) => c.state !== "closed");
    const degraded = Boolean(openCircuit);

    return {
      status: "ok",
      service: "sdk-proxy",
      degraded,
      reason: degraded ? `provider circuit open: ${openCircuit.reason}` : null,
      concurrency: semaphore.stats(),
      circuits,
    };
  }

  return { run, record, health, semaphore, breaker };
}
