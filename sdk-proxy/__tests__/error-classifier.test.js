import test from "node:test";
import assert from "node:assert/strict";
import {
  classifyError,
  opensCircuit,
  parseStatusFromText,
  toErrorBody,
} from "../error-classifier.js";

test("the incident error is permanent, not transient", () => {
  const err = Object.assign(
    new Error(
      "Anthropic API error (400): You're out of extra usage. Add more at claude.ai/settings/usage and keep going.",
    ),
    { status: 400 },
  );
  const info = classifyError(err);
  assert.equal(info.reason, "quota_exhausted");
  assert.equal(info.retryable, false);
  assert.equal(opensCircuit(info), true);
});

test("recovers the real status from a subprocess that only says 'exited with code 1'", () => {
  const err = new Error("Claude Code process exited with code 1");
  const stderr = 'API Error: 400 {"type":"error","error":{"message":"You\'re out of extra usage."}}';
  const info = classifyError(err, { stderr });
  assert.equal(info.reason, "quota_exhausted");
  assert.equal(info.retryable, false);
});

test("a bare 'exited with code 1' with no stderr is not retried", () => {
  // Unknown defaults to permanent on purpose: treating the unclassifiable as
  // retryable is what turned one bad credential into a host-wide outage.
  const info = classifyError(new Error("Claude Code process exited with code 1"));
  assert.equal(info.reason, "unknown");
  assert.equal(info.retryable, false);
  assert.equal(opensCircuit(info), false, "unknown must not open the circuit on its own");
});

test("classifies transient failures as retryable", () => {
  for (const [status, reason] of [[429, "rate_limited"], [500, "server_error"], [503, "server_error"], [408, "timeout"]]) {
    const info = classifyError(Object.assign(new Error("boom"), { status }));
    assert.equal(info.reason, reason, `status ${status}`);
    assert.equal(info.retryable, true, `status ${status} should be retryable`);
  }
});

test("classifies permanent auth failures", () => {
  for (const [status, reason] of [[401, "auth_invalid"], [403, "forbidden"], [404, "model_not_found"], [422, "invalid_request"]]) {
    const info = classifyError(Object.assign(new Error("boom"), { status }));
    assert.equal(info.reason, reason, `status ${status}`);
    assert.equal(info.retryable, false, `status ${status} must not be retried`);
  }
});

test("local port exhaustion is never retried", () => {
  const info = classifyError(new Error("connect EADDRNOTAVAIL 160.79.104.10:443"));
  assert.equal(info.reason, "local_port_exhaustion");
  assert.equal(info.retryable, false);
  assert.equal(opensCircuit(info), true, "must stop dialling, retrying makes it worse");
});

test("plain socket errors stay retryable", () => {
  const info = classifyError(new Error("connect ECONNRESET 1.2.3.4:443"));
  assert.equal(info.reason, "network_error");
  assert.equal(info.retryable, true);
});

test("honours an explicit verdict instead of re-deriving from status", () => {
  const circuitOpen = Object.assign(new Error("provider circuit open: quota_exhausted"), {
    status: 503,
    reason: "quota_exhausted",
    retryable: false,
  });
  const info = classifyError(circuitOpen);
  assert.equal(info.retryable, false, "a 503 from an open circuit is not a retryable server error");
  assert.equal(info.status, 503);
});

test("honours Retry-After", () => {
  const err = Object.assign(new Error("slow down"), { status: 429, headers: { "retry-after": "30" } });
  const info = classifyError(err);
  assert.equal(info.retryAfterMs, 30000);
  assert.equal(toErrorBody(info).retry_after_ms, 30000);
});

test("parseStatusFromText ignores non-HTTP numbers", () => {
  assert.equal(parseStatusFromText("processed 400 tokens"), null);
  assert.equal(parseStatusFromText("API Error: 529 overloaded"), 529);
});

test("wire format carries the machine-readable verdict", () => {
  const body = toErrorBody(classifyError(Object.assign(new Error("nope"), { status: 401 })));
  assert.deepEqual(body, {
    error: { message: "nope", type: "auth_invalid" },
    retryable: false,
    reason: "auth_invalid",
  });
});
