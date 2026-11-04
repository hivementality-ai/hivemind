// Keeps one live Claude Code process per Hivemind session between turns.
//
// Without it every chat turn spawns a fresh subprocess and pays its startup
// cost. With it the first turn spawns the process in streaming-input mode and
// later turns write their prompt to the same process. The pool is bounded
// (LRU cap, idle reap) because each entry is a real subprocess, and any
// doubt (config change, history mismatch, crash, abort) discards the entry so
// the next turn starts fresh, which is exactly today's behavior.

import { createHash } from "node:crypto";

/**
 * Push-based async iterable used as the SDK's streaming input.
 * @returns {{iterable: AsyncIterable<object>, push: (item: object) => void, end: () => void}}
 */
export function createInputChannel() {
  const queue = [];
  let waiter = null;
  let ended = false;

  const iterable = {
    [Symbol.asyncIterator]() {
      return {
        next() {
          if (queue.length) return Promise.resolve({ value: queue.shift(), done: false });
          if (ended) return Promise.resolve({ value: undefined, done: true });
          return new Promise((resolve) => { waiter = resolve; });
        },
        return() {
          ended = true;
          return Promise.resolve({ value: undefined, done: true });
        },
      };
    },
  };

  return {
    iterable,
    push(item) {
      if (ended) return;
      if (waiter) {
        const resolve = waiter;
        waiter = null;
        resolve({ value: item, done: false });
      } else {
        queue.push(item);
      }
    },
    end() {
      ended = true;
      if (waiter) {
        const resolve = waiter;
        waiter = null;
        resolve({ value: undefined, done: true });
      }
    },
  };
}

/**
 * Stable fingerprint of everything that is fixed when a process is spawned.
 * @param {object} config model, system prompt, tool definitions, credential, etc.
 * @returns {string}
 */
export function configKey(config) {
  return createHash("sha256").update(JSON.stringify(config)).digest("hex");
}

/**
 * Splits a system prompt into its stable part and the per-turn dynamic block
 * that Rails appends last. Returns null when the prompt does not end with that
 * block, so callers treat the whole prompt as stable (today's behavior).
 * @param {string|Array<{text?: string}>|null} systemPrompt
 * @param {string|null} dynamicText the dynamic block's text as Rails sent it
 * @returns {{staticText: string, dynamicText: string}|null}
 */
export function splitDynamic(systemPrompt, dynamicText) {
  if (!dynamicText || !Array.isArray(systemPrompt) || systemPrompt.length === 0) return null;
  if (systemPrompt.at(-1)?.text !== dynamicText) return null;
  const staticText = systemPrompt.slice(0, -1).map((b) => b.text).filter(Boolean).join("\n\n");
  return { staticText, dynamicText };
}

/**
 * Picks the system text a turn starts a process with. A warm-eligible request
 * with a splittable dynamic block gets the static text only, and the dynamic
 * text travels as prompt context instead, so every turn uses one path.
 * @param {string|Array<{text?: string}>|null} systemPrompt
 * @param {string|null} systemDynamic
 * @param {boolean} warmEligible whether this request may use a warm process
 * @param {string|null} fullText the whole system prompt flattened to text
 * @returns {{systemText: string|null, dynamicText: string|null}}
 */
export function systemForTurn(systemPrompt, systemDynamic, warmEligible, fullText) {
  const split = warmEligible ? splitDynamic(systemPrompt, systemDynamic) : null;
  if (!split) return { systemText: fullText, dynamicText: null };
  return { systemText: split.staticText, dynamicText: split.dynamicText };
}

/**
 * Prefixes a prompt with fresh per-turn context.
 * @param {string} prompt
 * @param {string} dynamicText
 * @returns {string}
 */
export function withTurnContext(prompt, dynamicText) {
  return `<turn_context>\nContext for this turn (replaces any earlier turn_context):\n${dynamicText}\n</turn_context>\n\n${prompt}`;
}

/** One live process and its turn bookkeeping. */
class WarmEntry {
  constructor({ sessionId, key, queryFn, options, now }) {
    this.sessionId = sessionId;
    this.key = key;
    this.busy = false;
    this.dead = false;
    this.messageCount = 0;
    this.dynamicText = null;
    this.lastUsedAt = now();
    this.abortController = new AbortController();
    this.input = createInputChannel();
    this.query = queryFn({
      prompt: this.input.iterable,
      options: { ...options, abortController: this.abortController },
    });
  }

  /** Stop the process. Safe to call more than once. */
  close() {
    if (this.dead) return;
    this.dead = true;
    this.input.end();
    try { this.abortController.abort(); } catch { /* already aborted */ }
    try { this.query.return?.(undefined)?.catch?.(() => {}); } catch { /* generator already finished */ }
  }

  /**
   * Send one user prompt and yield messages up to and including the turn's
   * result. If the process ends first, the entry is dead and this throws
   * (unless the turn was aborted, which just ends the stream).
   * @param {string} prompt
   * @returns {AsyncGenerator<object>}
   */
  async *turn(prompt) {
    this.input.push({
      type: "user",
      message: { role: "user", content: prompt },
      parent_tool_use_id: null,
      session_id: "",
    });
    let finished = false;
    try {
      while (true) {
        const { value, done } = await this.query.next();
        if (done) {
          if (this.dead) return;
          throw new Error("Claude Code process ended before the turn finished");
        }
        yield value;
        if (value?.type === "result") {
          finished = true;
          return;
        }
      }
    } finally {
      if (!finished) this.close();
    }
  }
}

/**
 * @param {object} opts
 * @param {Function} opts.queryFn      the SDK's query()
 * @param {number} [opts.maxWarm]      most live processes held at once
 * @param {number} [opts.idleMs]       idle time before a process is reaped
 * @param {() => number} [opts.now]
 * @param {object} [opts.logger]
 */
export function createWarmPool({ queryFn, maxWarm = 4, idleMs = 10 * 60 * 1000, now = Date.now, logger = console }) {
  const entries = new Map(); // insertion order doubles as LRU order
  let timer = null;

  function discard(entry) {
    entry.close();
    if (entries.get(entry.sessionId) === entry) entries.delete(entry.sessionId);
  }

  /** Close every idle entry that has outlived idleMs. @returns {number} reaped */
  function reap() {
    let reaped = 0;
    for (const entry of [...entries.values()]) {
      if (entry.dead || (!entry.busy && now() - entry.lastUsedAt >= idleMs)) {
        logger.log(`[warm] reaping session=${entry.sessionId}`);
        discard(entry);
        reaped += 1;
      }
    }
    return reaped;
  }

  function ensureTimer() {
    if (timer) return;
    timer = setInterval(reap, Math.max(1000, Math.min(idleMs, 60_000)));
    timer.unref?.();
  }

  /**
   * Take the idle entry for a session if it is still valid for this turn.
   * A stale entry (config changed, history diverged, dead) is discarded.
   * @param {string} sessionId
   * @param {string} key              configKey for this request
   * @param {number} messageCount     conversation messages in this request
   * @returns {WarmEntry|null}
   */
  function checkout(sessionId, key, messageCount) {
    const entry = entries.get(sessionId);
    if (!entry || entry.busy) return null;
    // Rails resends the whole history. The process already holds all of it
    // plus its own reply, so exactly one message (the new user turn) is new.
    if (entry.dead || entry.key !== key || entry.messageCount + 1 !== messageCount) {
      discard(entry);
      return null;
    }
    entry.busy = true;
    entries.delete(sessionId);
    entries.set(sessionId, entry);
    return entry;
  }

  /**
   * Spawn a new warm entry, evicting the least recently used idle one when
   * full. Returns null when every slot is busy so the caller runs cold.
   * @returns {WarmEntry|null}
   */
  function create(sessionId, key, options) {
    const existing = entries.get(sessionId);
    if (existing) {
      if (existing.busy) return null;
      discard(existing);
    }
    while (entries.size >= maxWarm) {
      const victim = [...entries.values()].find((e) => !e.busy);
      if (!victim) return null;
      logger.log(`[warm] evicting session=${victim.sessionId} (cap ${maxWarm})`);
      discard(victim);
    }
    const entry = new WarmEntry({ sessionId, key, queryFn, options, now });
    entry.busy = true;
    entries.set(sessionId, entry);
    ensureTimer();
    return entry;
  }

  /**
   * Hand an entry back after a turn. A failed or aborted turn discards it.
   * @param {WarmEntry} entry
   * @param {{ok: boolean, messageCount?: number}} outcome messageCount is the
   *   number of conversation messages the process now holds, its reply included
   */
  function release(entry, { ok, messageCount }) {
    entry.busy = false;
    if (!ok || entry.dead) {
      discard(entry);
      return;
    }
    entry.messageCount = messageCount;
    entry.lastUsedAt = now();
  }

  /**
   * Open one turn on a warm process, reusing or spawning as needed, or fall
   * back to `cold()` when no slot is free.
   * @param {object} opts
   * @param {string} opts.sessionId
   * @param {string} opts.key            configKey for this request
   * @param {number} opts.messageCount   conversation messages in this request
   * @param {string} opts.prompt         the new user message
   * @param {object} opts.options        SDK options used if a process is spawned
   * @param {object} opts.sink           per-request callbacks the process
   *   reaches through; merged into the entry's sink when it is reused
   * @param {() => object} opts.cold     builds the uncached turn
   * @param {string|null} [opts.dynamicText] this request's per-turn system block
   * @returns {{messages: AsyncIterable<object>, warm: boolean, finish: (ok: boolean) => void, abort: () => void}}
   */
  function openTurn({ sessionId, key, messageCount, prompt, options, sink, cold, dynamicText = null }) {
    let entry = checkout(sessionId, key, messageCount);
    let turnPrompt = prompt;
    if (entry) {
      logger.log(`[warm] reusing session=${sessionId}`);
      Object.assign(entry.sink, sink);
      // Only a block that changed since this process last saw one needs to
      // reach it again, as context ahead of the prompt.
      if (dynamicText && dynamicText !== entry.dynamicText) turnPrompt = withTurnContext(prompt, dynamicText);
      entry.dynamicText = dynamicText;
    } else {
      entry = create(sessionId, key, options);
      if (!entry) return cold();
      // The process starts on the static system text, so the first turn's
      // context arrives the same way as every later change.
      if (dynamicText) turnPrompt = withTurnContext(prompt, dynamicText);
      entry.sink = sink;
      entry.dynamicText = dynamicText;
      logger.log(`[warm] started session=${sessionId}`);
    }
    return {
      messages: entry.turn(turnPrompt),
      warm: true,
      finish: (ok) => release(entry, { ok, messageCount: messageCount + 1 }),
      abort: () => entry.close(),
    };
  }

  /** Close everything, for shutdown. */
  function closeAll() {
    if (timer) { clearInterval(timer); timer = null; }
    for (const entry of [...entries.values()]) discard(entry);
  }

  return { checkout, create, release, openTurn, reap, closeAll, size: () => entries.size };
}
