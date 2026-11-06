import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

test("API-key path falls back to the newest Sonnet when no model is given", () => {
  const source = readFileSync(new URL("../server.js", import.meta.url), "utf8");
  assert.match(source, /model:\s*model \|\| "claude-sonnet-5-5"/);
});
