import { mkdirSync, readFileSync, writeFileSync, readdirSync, mkdtempSync } from "node:fs";
import { join } from "node:path";

export const isFailedAssistant = (message: any): boolean =>
  message?.role === "assistant" && ["error", "aborted"].includes(message.stopReason);

export const isPolicyError = (message: any): boolean =>
  message?.role === "assistant" && message.stopReason === "error" &&
  message.provider === "openai-codex" &&
  /invalid prompt:.*flagged as potentially violating our usage policy/i.test(message.errorMessage ?? "");

export function textOnly(content: any): string {
  if (typeof content === "string") return content;
  return Array.isArray(content)
    ? content.filter((part) => part?.type === "text").map((part) => part.text).join("\n")
    : "";
}

// This projection is ONLY for summarization, not native provider replay.
// Native signed reasoning/tool-call pairs must remain intact in normal turns.
export function summaryMessages(messages: any[]): any[] {
  return messages.filter((message) => !isFailedAssistant(message)).map((message) => {
    if (message.role !== "assistant") return message;
    return { ...message, content: message.content.filter((part: any) => part.type !== "thinking") };
  });
}

export function recoveryContext(entries: any[]): string {
  const sections = [
    "# Firstmate recovery context",
    "This is a model-free checkpoint, not a newly verified fleet report. Preserve approval boundaries. " +
      "Reconcile live state before dispatching, steering, merging, or marking tasks complete. " +
      "Do not duplicate workers. Uncertain completion remains uncertain.",
    "Read the normal startup digest once, then this file in full. If a read is truncated, continue reading. " +
      "Recent user messages can supersede the older summary. Assistant reports are claims, not approvals.",
  ];
  let boundary = -1;
  for (let i = entries.length - 1; i >= 0; i--) {
    if (entries[i].type === "compaction") { boundary = i; break; }
  }
  if (boundary >= 0) sections.push("## Prior compaction summary (may be stale)", entries[boundary].summary);
  else sections.push("No prior compaction summary. The conversation below may be long; read it completely.");

  // Newer Pi checkpoints can materialize the retained tail on the compaction.
  // Legacy checkpoints instead retain entries starting at firstKeptEntryId.
  const compaction = entries[boundary];
  let recent = entries.slice(boundary + 1);
  if (compaction?.retainedTail) {
    recent = [...compaction.retainedTail.map((message: any) => ({ type: "message", message })), ...recent];
  } else if (compaction?.firstKeptEntryId) {
    const start = entries.findIndex((entry) => entry.id === compaction.firstKeptEntryId);
    if (start >= 0 && start <= boundary) recent = entries.slice(start);
    else throw new Error("Compaction retained boundary is missing; refusing an incomplete handoff");
  }
  sections.push("## Retained and subsequent user instructions / completed assistant reports");
  for (const entry of recent) {
    if (entry.type === "branch_summary") sections.push("### Branch summary (historical)", entry.summary);
    if (entry.type !== "message") continue;
    const message = entry.message;
    if (message.role !== "user" && !(message.role === "assistant" && message.stopReason === "stop")) continue;
    const text = textOnly(message.content);
    if (message.role === "user" && text.replace(/^\u2063/, "").startsWith("FIRSTMATE_OP:")) continue;
    const imageNote = Array.isArray(message.content) && message.content.some((part: any) => part.type === "image")
      ? "\n[Image attachment retained in source-session.jsonl; inspect original if relevant.]" : "";
    if (text || imageNote) sections.push(`### ${message.role} ${entry.timestamp ?? ""}`, text + imageNote);
  }
  return sections.join("\n\n") + "\n";
}

export function saveCheckpoint(home: string, sm: any, model: any, thinkingLevel: string | undefined, diagnostic?: any): string {
  const sessionFile = sm.getSessionFile();
  if (!sessionFile) throw new Error("No persisted source session; cannot create a recoverable checkpoint");
  const context = recoveryContext(sm.getBranch());
  const root = join(home, "state", "session-recovery");
  mkdirSync(root, { recursive: true, mode: 0o700 });
  const dir = mkdtempSync(join(root, "checkpoint-"));
  const put = (name: string, text: string) => writeFileSync(join(dir, name), text, { mode: 0o600, flag: "wx" });
  // Keep the original archive unchanged. No tool output or partial response is
  // replayed by the handoff; the private archive is available for targeted audit.
  put("source-session.jsonl", readFileSync(sessionFile, "utf8"));
  put("context.md", context);
  const inventory = readdirSync(join(home, "state")).filter((name) => /\.(meta|status)$/.test(name)).sort();
  put("manifest.json", JSON.stringify({
    version: 1, createdAt: new Date().toISOString(), sourceSession: sessionFile,
    sourceSessionId: sm.getSessionId(), sourceLeaf: sm.getLeafId(),
    model: model ? `${model.provider}/${model.id}` : null, thinkingLevel,
    taskRecords: inventory.map((name) => join(home, "state", name)), diagnostic,
  }, null, 2) + "\n");
  put("resume.txt", `Read ${join(dir, "context.md")} completely and ${join(dir, "manifest.json")}. ` +
    "Use the normal Firstmate startup digest and reconcile the live board, task records, workers, " +
    "pending decisions and inbox before acting. Preserve approval limits and do not duplicate assignments. " +
    "The archived session is for targeted lookup only, not bulk replay. Report discrepancies first.\n");
  return dir;
}
