// Single classification point for every provider failure the proxy can see.
//
// The distinction that matters is not "what went wrong" but "will dialling
// again ever help". A 400 "You're out of extra usage" is a human-actionable
// permanent failure: retrying it opens a fresh TCP connection per attempt and
// burns the host's ephemeral port pool for nothing. Callers must be able to
// tell that apart from a 503 without string-matching, so every error leaves
// this module as { retryable, reason, status }.

const QUOTA_PATTERNS = [
  /out of extra usage/i,
  /credit balance is too low/i,
  /insufficient[_\s-]?quota/i,
  /billing[_\s-]?(?:hard[_\s-]?)?limit/i,
  /purchase (?:more )?credits/i,
  /add more at claude\.ai\/settings\/usage/i,
];

const AUTH_PATTERNS = [
  /invalid[_\s-]?api[_\s-]?key/i,
  /authentication[_\s-]?error/i,
  /oauth token (?:has )?expired/i,
  /invalid bearer token/i,
  /unauthorized/i,
];

const MODEL_NOT_FOUND_PATTERNS = [
  /model[:\s].*not[_\s-]?found/i,
  /not_found_error/i,
  /unknown model/i,
];

// Local resource exhaustion. Deliberately NOT retryable: EADDRNOTAVAIL means
// the kernel has no ephemeral port left, and every retry makes that worse.
// This is the exact failure mode of the 2026-08-24 host outage.
const LOCAL_EXHAUSTION_PATTERNS = [
  /EADDRNOTAVAIL/,
  /can't assign requested address/i,
  /EMFILE/,
  /ENFILE/,
  /too many open files/i,
];

const NETWORK_PATTERNS = [
  /ECONNRESET/, /ECONNREFUSED/, /EPIPE/, /ENOTFOUND/, /EAI_AGAIN/,
  /ETIMEDOUT/, /ESOCKETTIMEDOUT/, /socket hang up/i,
  /network[_\s-]?error/i, /connection error/i,
];

const OVERLOAD_PATTERNS = [
  /overloaded/i, /rate[_\s-]?limit/i, /too many requests/i,
];

/** Reasons that must never be retried against the same credential. */
export const PERMANENT_REASONS = Object.freeze([
  "quota_exhausted",
  "auth_invalid",
  "forbidden",
  "model_not_found",
  "invalid_request",
  "request_too_large",
  "local_port_exhaustion",
  "unknown",
]);

/** Reasons that count toward opening the per-credential circuit. */
export const CIRCUIT_REASONS = Object.freeze([
  "quota_exhausted",
  "auth_invalid",
  "forbidden",
  "local_port_exhaustion",
]);

const matchesAny = (patterns, text) => patterns.some((p) => p.test(text));

/**
 * Recover an HTTP status that got flattened into a text blob.
 *
 * The OAuth path fails as `Claude Code process exited with code 1`, which
 * erases the underlying status. The real cause is only visible in the
 * subprocess's stderr, in shapes like `API Error: 400 {"type":"error",...}`
 * or `Anthropic API error (429)`.
 */
export function parseStatusFromText(text) {
  if (!text) return null;
  const patterns = [
    /API Error:?\s*(\d{3})\b/i,
    /\berror\s*\((\d{3})\)/i,
    /\bstatus(?:\s*code)?[:\s]+(\d{3})\b/i,
    /\bHTTP\s+(\d{3})\b/i,
    /"status"\s*:\s*(\d{3})\b/,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match) {
      const status = Number(match[1]);
      if (status >= 400 && status <= 599) return status;
    }
  }
  return null;
}

function reasonForStatus(status, text) {
  switch (true) {
    case status === 400:
      return matchesAny(QUOTA_PATTERNS, text) ? "quota_exhausted" : "invalid_request";
    case status === 401:
      return "auth_invalid";
    case status === 402:
      return "quota_exhausted";
    case status === 403:
      return "forbidden";
    case status === 404:
      return "model_not_found";
    case status === 408:
      return "timeout";
    case status === 409:
      return "conflict";
    case status === 413:
      return "request_too_large";
    case status === 422:
      return "invalid_request";
    case status === 429:
      return "rate_limited";
    case status >= 500 && status <= 599:
      return "server_error";
    default:
      return null;
  }
}

function reasonFromText(text) {
  // Order matters: local exhaustion and quota are checked before the generic
  // network patterns, because their messages often contain both.
  if (matchesAny(LOCAL_EXHAUSTION_PATTERNS, text)) return "local_port_exhaustion";
  if (matchesAny(QUOTA_PATTERNS, text)) return "quota_exhausted";
  if (matchesAny(AUTH_PATTERNS, text)) return "auth_invalid";
  if (matchesAny(MODEL_NOT_FOUND_PATTERNS, text)) return "model_not_found";
  if (matchesAny(OVERLOAD_PATTERNS, text)) return "rate_limited";
  if (matchesAny(NETWORK_PATTERNS, text)) return "network_error";
  return null;
}

function statusForReason(reason, fallback) {
  if (fallback) return fallback;
  const map = {
    quota_exhausted: 402,
    auth_invalid: 401,
    forbidden: 403,
    model_not_found: 404,
    invalid_request: 400,
    request_too_large: 413,
    rate_limited: 429,
    timeout: 504,
    conflict: 409,
    server_error: 502,
    network_error: 502,
    local_port_exhaustion: 503,
    circuit_open: 503,
    load_shed: 429,
  };
  return map[reason] || 500;
}

function parseRetryAfterMs(err) {
  const header = err?.headers?.["retry-after"] ?? err?.responseHeaders?.["retry-after"];
  if (header == null) return null;
  const seconds = Number(header);
  return Number.isFinite(seconds) && seconds >= 0 ? Math.round(seconds * 1000) : null;
}

/**
 * Classify a provider failure.
 *
 * @param {unknown} err          the thrown error
 * @param {object}  [context]
 * @param {string}  [context.stderr]  captured subprocess stderr (OAuth path)
 * @returns {{retryable: boolean, reason: string, status: number,
 *            message: string, retryAfterMs: number|null}}
 */
export function classifyError(err, context = {}) {
  const message = String(err?.message ?? err ?? "Unknown error");
  const stderr = String(context.stderr || "");
  const haystack = `${message}\n${stderr}`;

  // Errors we raised ourselves already carry an authoritative verdict
  // (circuit open, load shed). Never re-derive it from their HTTP status —
  // a 503 from an open circuit is emphatically not a retryable server error.
  if (typeof err?.reason === "string" && typeof err?.retryable === "boolean") {
    return {
      retryable: err.retryable,
      reason: err.reason,
      status: Number.isInteger(err.status) ? err.status : statusForReason(err.reason, null),
      message,
      retryAfterMs: Number.isInteger(err.retryAfterMs) ? err.retryAfterMs : parseRetryAfterMs(err),
    };
  }

  // An explicit numeric status on the error object is the strongest signal;
  // otherwise dig it back out of the text the subprocess left behind.
  const explicitStatus =
    Number.isInteger(err?.status) ? err.status :
    Number.isInteger(err?.statusCode) ? err.statusCode :
    parseStatusFromText(haystack);

  const reason =
    (explicitStatus && reasonForStatus(explicitStatus, haystack)) ||
    reasonFromText(haystack) ||
    "unknown";

  return {
    retryable: !PERMANENT_REASONS.includes(reason),
    reason,
    status: statusForReason(reason, explicitStatus),
    message,
    retryAfterMs: parseRetryAfterMs(err),
  };
}

/** Should this classification count toward opening the credential's circuit? */
export function opensCircuit(classification) {
  return CIRCUIT_REASONS.includes(classification.reason);
}

/** Wire format shared with the Rails side (Providers::ErrorClassifier). */
export function toErrorBody(classification) {
  return {
    error: { message: classification.message, type: classification.reason },
    retryable: classification.retryable,
    reason: classification.reason,
    ...(classification.retryAfterMs != null
      ? { retry_after_ms: classification.retryAfterMs }
      : {}),
  };
}
