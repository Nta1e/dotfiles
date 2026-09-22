import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { isPolicyError, saveCheckpoint, summaryMessages } from "./lib.ts";

const home = join(homedir(), "workspace", "firstmate");
const marker = "firstmate-recovery";

export default function (pi: ExtensionAPI) {
  const enabled = (ctx: ExtensionContext): boolean => {
    try { return realpathSync(ctx.cwd) === realpathSync(home); }
    catch { return false; }
  };
  let request: Record<string, unknown> | undefined;
  let requestId: string | undefined;
  let lastCheckpoint: string | undefined;

  pi.on("before_provider_request", (event, ctx) => {
    if (!enabled(ctx)) return;
    const payload = JSON.stringify(event.payload);
    request = {
      timestamp: new Date().toISOString(),
      bytes: Buffer.byteLength(payload),
      sha256: createHash("sha256").update(payload).digest("hex"),
    };
    requestId = undefined;
    // Never persist raw payloads, HTTP headers, credentials or image data here.
  });
  pi.on("after_provider_response", (event, ctx) => {
    if (!enabled(ctx)) return;
    requestId = event.headers["x-request-id"] ?? event.headers["request-id"];
  });

  pi.on("session_before_compact", (event, ctx) => {
    if (!enabled(ctx)) return;
    // Pi 0.85.1 passes this preparation by reference to its default summarizer.
    // Keep the native cut point, file tracking, summary generation and accounting.
    event.preparation.messagesToSummarize = summaryMessages(event.preparation.messagesToSummarize);
    event.preparation.turnPrefixMessages = summaryMessages(event.preparation.turnPrefixMessages);
  });

  pi.on("agent_end", (event, ctx) => {
    if (!enabled(ctx)) return;
    const message = event.messages.at(-1);
    if (!isPolicyError(message)) return;
    const diagnostic = {
      kind: "provider-policy-rejection", request, requestId,
      responseId: (message as any).responseId,
      timestamp: new Date().toISOString(),
    };
    try {
      lastCheckpoint = saveCheckpoint(home, ctx.sessionManager, ctx.model, ctx.thinkingLevel, diagnostic);
      pi.appendEntry(marker, { checkpoint: lastCheckpoint, ...diagnostic });
      ctx.ui.notify(`Codex rejected the request. Recovery checkpoint: ${lastCheckpoint}. ` +
        "No retry or model switch was initiated by recovery. Use /fm-recovery for instructions.", "warning");
    } catch (error) {
      ctx.ui.notify(`Could not save recovery checkpoint: ${String(error)}. Original session remains intact.`, "error");
    }
  });

  pi.on("session_start", (_event, ctx) => {
    if (!enabled(ctx)) return;
    lastCheckpoint = undefined;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type === "custom" && entry.customType === marker) {
        lastCheckpoint = (entry.data as any)?.checkpoint;
      }
    }
  });

  pi.registerCommand("fm-checkpoint", {
    description: "Save a private, model-free Firstmate handoff without resetting the session or workers",
    handler: async (_args, ctx) => {
      if (!enabled(ctx)) return ctx.ui.notify("This command is only for the primary Firstmate home.", "warning");
      try {
        // A read-only checkpoint is safe during a turn. Firstmate also retains
        // nextTurn notices while idle, so pending messages cannot gate backups.
        lastCheckpoint = saveCheckpoint(home, ctx.sessionManager, ctx.model, ctx.thinkingLevel, {
          kind: "manual-checkpoint", inFlight: !ctx.isIdle(), pendingMessages: ctx.hasPendingMessages(),
        });
        pi.appendEntry(marker, { checkpoint: lastCheckpoint });
        ctx.ui.notify(`Saved ${lastCheckpoint}. /fm-recovery shows the refresh steps.`, "info");
      } catch (error) {
        ctx.ui.notify(`Checkpoint failed: ${String(error)}. Session and workers unchanged.`, "error");
      }
    },
  });

  pi.registerCommand("fm-recovery", {
    description: "Show the last checkpoint and safe session-refresh steps (no model call)",
    handler: async (_args, ctx) => {
      if (!enabled(ctx)) return;
      ctx.ui.notify(lastCheckpoint
        ? `Checkpoint: ${lastCheckpoint}\n` +
          "If work continued since this checkpoint, run /fm-checkpoint again first.\n" +
          "Wait for the current turn to finish before refreshing.\n" +
          "To refresh: /new, then /model openai-codex/gpt-5.5 and /thinking medium.\n" +
          `Then send: Read ${join(lastCheckpoint, "resume.txt")} and follow its recovery instructions.\n` +
          "This replaces conversation context, not worker processes or worktrees. Old history remains available via /resume."
        : "No checkpoint in this session. Run /fm-checkpoint first. No reset is required if work has recovered.", "info");
    },
  });
}
