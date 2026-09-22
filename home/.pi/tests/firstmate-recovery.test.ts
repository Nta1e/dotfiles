import assert from "node:assert/strict";
import { test, after } from "node:test";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isPolicyError, summaryMessages, recoveryContext, saveCheckpoint } from "../agent/extensions/firstmate-recovery/lib.ts";

const temp = mkdtempSync(join(tmpdir(), "fm-recovery-test-"));
const home = join(temp, "workspace", "firstmate");
mkdirSync(join(home, "state"), { recursive: true });
const oldHome = process.env.HOME;
process.env.HOME = temp;
const { default: install } = await import("../agent/extensions/firstmate-recovery/index.ts");
process.env.HOME = oldHome;
after(() => rmSync(temp, { recursive: true, force: true }));

const message = (role: string, text: string, stopReason?: string) => ({
  role, content: [{ type: "text", text }], stopReason,
});
const policy = { ...message("assistant", "FAILED PARTIAL", "error"), provider: "openai-codex",
  errorMessage: "Codex error: Invalid prompt: your prompt was flagged as potentially violating our usage policy.",
  responseId: "resp_test" };
const entries: any[] = [
  { type: "message", id: "old", message: message("user", "OLD MESSAGE") },
  { type: "message", id: "keep", message: message("user", "Do not merge without asking") },
  { type: "compaction", id: "compact", summary: "Historical summary", firstKeptEntryId: "keep" },
  { type: "message", message: policy },
  { type: "message", message: message("assistant", "COMMENTARY", "toolUse") },
  { type: "message", message: message("user", "\u2063FIRSTMATE_OP: v1 watcher: noise") },
  { type: "message", message: { role: "user", content: [{ type: "image", data: "IMAGE" }] } },
  { type: "message", message: message("assistant", "Completed report", "stop") },
  { type: "message", message: message("toolResult", "TOOL OUTPUT") },
];
const source = join(temp, "session.jsonl");
writeFileSync(source, entries.map((e) => JSON.stringify(e)).join("\n") + "\n");
const sm = { getSessionFile: () => source, getBranch: () => entries, getSessionId: () => "test-session", getLeafId: () => "leaf" };
const model = { provider: "openai-codex", id: "gpt-5.5" };

function fixture() {
  const handlers: Record<string, Function> = {};
  const commands: Record<string, any> = {};
  const notices: string[] = [];
  const appended: any[] = [];
  const pi = { on: (name: string, fn: Function) => handlers[name] = fn,
    registerCommand: (name: string, command: any) => commands[name] = command,
    appendEntry: (...args: any[]) => appended.push(args) };
  install(pi as any);
  const ctx = { cwd: home, sessionManager: sm, model, thinkingLevel: "medium",
    isIdle: () => true, hasPendingMessages: () => false,
    ui: { notify: (text: string) => notices.push(text) } };
  return { handlers, commands, notices, appended, ctx };
}

test("only the exact Codex policy error triggers recovery", () => {
  assert.equal(isPolicyError(policy), true);
  for (const override of [{ stopReason: "stop" }, { provider: "anthropic" }, { errorMessage: "fetch failed" },
    { errorMessage: "Provided authentication token is expired." }, { errorMessage: "The usage limit has been reached" }]) {
    assert.equal(isPolicyError({ ...policy, ...override }), false);
  }
});

test("summary projection removes partial outputs and thinking, preserves calls/results and original", () => {
  const input = [policy, message("assistant", "ABORTED", "aborted"), {
    ...message("assistant", "Visible result", "toolUse"), content: [
      { type: "thinking", thinking: "THINKING", thinkingSignature: "signed" },
      { type: "text", text: "Visible result" }, { type: "toolCall", id: "call", name: "read", arguments: {} },
    ],
  }, message("toolResult", "Observed evidence")];
  const before = structuredClone(input);
  const projected = summaryMessages(input);
  assert.deepEqual(input, before);
  assert.equal(projected.length, 2);
  assert.deepEqual(projected[0].content.map((p: any) => p.type), ["text", "toolCall"]);
  assert.equal(projected[1], input[3]);
});

test("legacy compaction handoff retains approvals, omits raw tools/partial output, marks images", () => {
  const text = recoveryContext(entries);
  for (const expected of ["Historical summary", "Do not merge without asking", "Completed report", "Image attachment"]) {
    assert.ok(text.includes(expected));
  }
  for (const absent of ["OLD MESSAGE", "FAILED PARTIAL", "COMMENTARY", "TOOL OUTPUT", "watcher: noise"]) {
    assert.ok(!text.includes(absent));
  }
});

test("materialized retained tails are included without replaying pre-compaction history", () => {
  const text = recoveryContext([
    entries[0], { type: "compaction", summary: "Summary", retainedTail: [message("user", "Retained approval limit")] },
  ]);
  assert.ok(text.includes("Retained approval limit"));
  assert.ok(!text.includes("OLD MESSAGE"));
});

test("a missing legacy retained boundary refuses an incomplete checkpoint", () => {
  assert.throws(() => recoveryContext([{ type: "compaction", summary: "x", firstKeptEntryId: "missing" }]), /boundary/);
});

test("checkpoint archives source unchanged with private permissions and fleet pointers", () => {
  writeFileSync(join(home, "state", "worker.meta"), "do not mutate");
  const before = readFileSync(source, "utf8");
  const dir = saveCheckpoint(home, sm, model, "medium");
  assert.equal(readFileSync(join(dir, "source-session.jsonl"), "utf8"), before);
  assert.equal(readFileSync(source, "utf8"), before);
  assert.equal(statSync(dir).mode & 0o777, 0o700);
  for (const name of readdirSync(dir)) assert.equal(statSync(join(dir, name)).mode & 0o777, 0o600);
  const manifest = JSON.parse(readFileSync(join(dir, "manifest.json"), "utf8"));
  assert.equal(manifest.model, "openai-codex/gpt-5.5");
  assert.ok(manifest.taskRecords.includes(join(home, "state", "worker.meta")));
  assert.equal(readFileSync(join(home, "state", "worker.meta"), "utf8"), "do not mutate");
});

test("unsaved sessions fail safely", () => {
  assert.throws(() => saveCheckpoint(home, { getSessionFile: () => undefined }, model, "medium"), /persisted/);
});

test("compaction hook updates default summarizer inputs, not cut point or historical messages", () => {
  const { handlers, ctx } = fixture();
  const preparation = { messagesToSummarize: [policy], turnPrefixMessages: [policy], firstKeptEntryId: "keep", tokensBefore: 42 };
  handlers.session_before_compact({ preparation }, ctx);
  assert.deepEqual(preparation, { messagesToSummarize: [], turnPrefixMessages: [], firstKeptEntryId: "keep", tokensBefore: 42 });
  assert.equal(policy.content[0].text, "FAILED PARTIAL");
});

test("extension is inert outside primary Firstmate home", async () => {
  const { handlers, ctx, appended } = fixture();
  ctx.cwd = temp;
  const preparation = { messagesToSummarize: [policy], turnPrefixMessages: [] };
  handlers.session_before_compact({ preparation }, ctx);
  handlers.agent_end({ messages: [policy] }, ctx);
  assert.equal(preparation.messagesToSummarize.length, 1);
  assert.equal(appended.length, 0);
});

test("policy error saves diagnostic metadata but never sends/retries/resets a session", () => {
  // The stub deliberately supplies no prompt, retry, model-switch or new-session API.
  const { handlers, ctx, appended, notices } = fixture();
  handlers.before_provider_request({ payload: { instructions: "SECRET PROMPT" } }, ctx);
  handlers.after_provider_response({ headers: { "x-request-id": "req_test", authorization: "SECRET TOKEN" } }, ctx);
  handlers.agent_end({ messages: [policy] }, ctx);
  assert.equal(appended.length, 1);
  const diagnostic = appended[0][1];
  assert.equal(diagnostic.requestId, "req_test");
  assert.equal(diagnostic.responseId, "resp_test");
  assert.equal(diagnostic.request.sha256.length, 64);
  assert.ok(!JSON.stringify(diagnostic).includes("SECRET"));
  assert.ok(notices[0].includes("No retry"));
});

test("normal completions and network errors do not create checkpoints", () => {
  const { handlers, ctx, appended } = fixture();
  handlers.agent_end({ messages: [message("assistant", "ok", "stop")] }, ctx);
  handlers.agent_end({ messages: [{ ...policy, errorMessage: "fetch failed" }] }, ctx);
  assert.equal(appended.length, 0);
});

test("read-only checkpoint tolerates pending nextTurn notices and records in-flight state", async () => {
  const { commands, ctx, appended, notices } = fixture();
  ctx.isIdle = () => false;
  await commands["fm-checkpoint"].handler("", ctx);
  assert.equal(appended.length, 1);
  const first = JSON.parse(readFileSync(join(appended[0][1].checkpoint, "manifest.json"), "utf8"));
  assert.equal(first.diagnostic.inFlight, true);
  ctx.isIdle = () => true;
  ctx.hasPendingMessages = () => true;
  await commands["fm-checkpoint"].handler("", ctx);
  assert.equal(appended.length, 2);
  ctx.hasPendingMessages = () => false;
  await commands["fm-checkpoint"].handler("", ctx);
  await commands["fm-recovery"].handler("", ctx);
  assert.equal(appended.length, 3);
  assert.ok(notices.at(-1)!.includes("Wait for the current turn"));
  assert.ok(notices.at(-1)!.includes("/new"));
  assert.ok(notices.at(-1)!.includes("/model openai-codex/gpt-5.5"));
});
