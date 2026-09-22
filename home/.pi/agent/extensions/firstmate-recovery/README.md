# Firstmate session recovery (local only)

This extension is active only in `~/workspace/firstmate`, not in workers or other projects.
It is installed through the existing dotfiles-backed global Pi extensions directory.
Tested with Pi 0.85.1.

## Commands

- `/fm-checkpoint`: save a model-free handoff and private archive of the current persisted session.
- `/fm-recovery`: show the last checkpoint and refresh instructions without making a provider call.

To refresh after a repeated benign-task rejection:

1. Run `/fm-checkpoint` again if work has continued since the previous checkpoint.
2. Wait for the current turn to finish, then run `/new`.
3. Select `/model openai-codex/gpt-5.5` and `/thinking medium` (the operator's current coordinator preference; the manifest records the source model if that preference changes).
4. Send `Read <checkpoint-directory>/resume.txt and follow its recovery instructions.`

Do not use `/clone` or `/fork` as a clean reset: they copy conversation history.
The original session remains available through `/resume`.
Refreshing the conversation does not mean respawning workers or deleting worktrees.
Firstmate's own session lifecycle owns watcher/branch rebinding and startup reconciliation.
This extension never resets the session automatically.

## Behavior

A Codex `Invalid prompt ... flagged as potentially violating our usage policy` error saves a checkpoint and a local diagnostic record.
Other errors (quota, authentication, network) are not mislabeled as policy errors.
There is no automatic retry, model switch, prompt rewriting or provider fallback.
The existing Firstmate watcher can still initiate its normal later turns; this extension does not suspend supervision.

Before default compaction, the extension omits failed/aborted assistant responses and structured thinking blocks from the summarization input.
It retains user instructions, visible assistant text, tool calls/results, the native cut point, file tracking and default summary generation.
It does not strip native signed reasoning from normal provider requests or edit stored session history.
This preparation mutation was verified against the installed Pi 0.85.1 implementation; recheck on a Pi upgrade.

Checkpoints are under `~/workspace/firstmate/state/session-recovery/checkpoint-*`:

- `context.md`: previous compaction summary plus retained/subsequent user instructions and completed assistant reports, with image-reference notices.
- `source-session.jsonl`: full private archive for targeted investigation, not bulk reinjection.
- `manifest.json`: original session/leaf/model, task-record paths and diagnostic metadata.
- `resume.txt`: recovery instructions referring to these files and live fleet state.

Checkpoint directories are private (0700) and files are 0600.
Archives can contain sensitive conversation/tool data; do not upload them as bug reports without reviewing/redacting them.
Diagnostics keep payload size/hash and request/response IDs, not raw payloads or authorization headers.
The original compaction summary is already lossy; the checkpoint cannot certify that it contains every historical decision.
Live state must be reconciled, and older decisions can be looked up in the archive.
An in-flight checkpoint records only persisted messages; current streaming output can be absent.
Checkpoints are not automatically deleted and can be removed manually when no longer needed.

## Companion local fix

`~/workspace/firstmate/.pi/extensions/fm-branch-supervision.ts` now skips `stopReason: error|aborted` before copying assistant text into the supervision branch.
Its regression is in `tests/fm-pi-branch-extension.test.sh`.
These are uncommitted local changes in the third-party checkout, not an upstream publication.
Recheck/preserve them when updating Firstmate; the recovery extension does not patch upstream files automatically.

## Verification

From the dotfiles root:

```sh
node --test home/.pi/tests/firstmate-recovery.test.ts
```

From the Firstmate root:

```sh
bash tests/fm-pi-branch-extension.test.sh
```

The mirror regression first failed with five mirrored messages instead of three, then passed with the filter.
The recovery extension has 12 deterministic tests covering projections, retained-tail formats, preservation of approvals, private backups, diagnostics, scope and failure handling.

These changes fix observable context-handling defects and provide recovery, but do not establish the provider's internal rejection cause or guarantee zero future false positives.
