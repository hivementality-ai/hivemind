import test from "node:test";
import assert from "node:assert/strict";
import { CircuitBreaker, CircuitOpenError, credentialKey } from "../circuit-breaker.js";

const makeClock = () => {
  const clock = { t: 1_000_000 };
  clock.now = () => clock.t;
  clock.advance = (ms) => { clock.t += ms; };
  return clock;
};

test("opens after the threshold and then refuses to dial", () => {
  const clock = makeClock();
  const breaker = new CircuitBreaker({ failureThreshold: 3, openMs: 60_000, now: clock.now });
  const key = "cred";

  breaker.recordPermanentFailure(key, "quota_exhausted");
  breaker.recordPermanentFailure(key, "quota_exhausted");
  assert.doesNotThrow(() => breaker.check(key));

  breaker.recordPermanentFailure(key, "quota_exhausted");
  assert.equal(breaker.state(key), "open");
  assert.throws(() => breaker.check(key), CircuitOpenError);
});

test("an open circuit reports the real reason, not a generic outage", () => {
  const clock = makeClock();
  const breaker = new CircuitBreaker({ failureThreshold: 1, openMs: 60_000, now: clock.now });
  breaker.recordPermanentFailure("cred", "quota_exhausted", "You're out of extra usage.");
  try {
    breaker.check("cred");
    assert.fail("expected the circuit to refuse");
  } catch (err) {
    assert.equal(err.reason, "quota_exhausted");
    assert.equal(err.retryable, false);
    assert.ok(err.retryAfterMs > 0);
  }
});

test("half-opens after the cooldown and lets one probe through", () => {
  const clock = makeClock();
  const breaker = new CircuitBreaker({ failureThreshold: 1, openMs: 60_000, now: clock.now });
  breaker.recordPermanentFailure("cred", "auth_invalid");

  clock.advance(59_000);
  assert.throws(() => breaker.check("cred"));

  clock.advance(2_000);
  assert.equal(breaker.state("cred"), "half_open");
  assert.doesNotThrow(() => breaker.check("cred"), "probe is allowed");
});

test("a failed probe re-opens immediately, without re-counting to the threshold", () => {
  const clock = makeClock();
  const breaker = new CircuitBreaker({ failureThreshold: 3, openMs: 60_000, now: clock.now });
  for (let i = 0; i < 3; i++) breaker.recordPermanentFailure("cred", "quota_exhausted");
  clock.advance(61_000);
  assert.equal(breaker.state("cred"), "half_open");

  breaker.recordPermanentFailure("cred", "quota_exhausted");
  assert.equal(breaker.state("cred"), "open");
  assert.throws(() => breaker.check("cred"));
});

test("a successful probe closes the circuit", () => {
  const clock = makeClock();
  const breaker = new CircuitBreaker({ failureThreshold: 1, openMs: 1_000, now: clock.now });
  breaker.recordPermanentFailure("cred", "quota_exhausted");
  clock.advance(2_000);
  breaker.recordSuccess("cred");
  assert.equal(breaker.state("cred"), "closed");
  assert.doesNotThrow(() => breaker.check("cred"));
});

test("transient failures never open the circuit", () => {
  const breaker = new CircuitBreaker({ failureThreshold: 2, openMs: 1_000 });
  for (let i = 0; i < 50; i++) breaker.recordTransientFailure("cred");
  assert.equal(breaker.state("cred"), "closed");
});

test("one exhausted credential does not silence a healthy one", () => {
  const breaker = new CircuitBreaker({ failureThreshold: 1, openMs: 60_000 });
  breaker.recordPermanentFailure("broke", "quota_exhausted");
  assert.throws(() => breaker.check("broke"));
  assert.doesNotThrow(() => breaker.check("healthy"));
});

test("reset restores service immediately when a human fixes the credential", () => {
  const breaker = new CircuitBreaker({ failureThreshold: 1, openMs: 60_000 });
  breaker.recordPermanentFailure("cred", "quota_exhausted");
  breaker.reset("cred");
  assert.equal(breaker.state("cred"), "closed");
  assert.doesNotThrow(() => breaker.check("cred"));
});

test("credentialKey never leaks the token", () => {
  const key = credentialKey("sk-ant-oat01-supersecret");
  assert.equal(key.length, 12);
  assert.ok(!key.includes("supersecret"));
  assert.equal(key, credentialKey("sk-ant-oat01-supersecret"), "stable");
});

test("snapshot surfaces state for the health endpoint", () => {
  const breaker = new CircuitBreaker({ failureThreshold: 1, openMs: 60_000 });
  breaker.recordPermanentFailure("cred", "quota_exhausted", "out of extra usage");
  const [entry] = breaker.snapshot();
  assert.equal(entry.state, "open");
  assert.equal(entry.reason, "quota_exhausted");
  assert.equal(entry.consecutive_failures, 1);
  assert.ok(entry.opened_at);
  assert.equal(breaker.anyOpen(), true);
});
