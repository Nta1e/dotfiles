# Local model-independent Firstmate relay

## Captain commands

- `/fmreply <code> <answer>`: reply to the code in an escalated question.
- `/fmstatus`: read Firstmate's durable status without a model.

Plain free-text Hermes conversations still use its model. These two commands
bypass model/agent dispatch, even while a Hermes agent is busy or out of quota.
They only work in the captain's private Telegram chat.

## Installation in this local setup

- Hermes remains the **only** Telegram polling receiver.
- `/opt/data/plugins/firstmate-relay` links to this bind-mounted directory; the
  plugin is enabled. Its supported `pre_gateway_dispatch` hook explicitly applies
  gateway authorization, then asynchronously invokes the SSH transport. Both the
  transport and host independently verify the configured Telegram user allowlist.
- The hook passes a JSON envelope on stdin over the existing SSH identity with
  pinned known-host checking. Reply content is never interpolated into a shell.
- Host service: `home/hermes/fm-telegram-relay.py`; SQLite correlation/outbox ledger
  under `~/workspace/firstmate/state/telegram-relay/`, private permissions.
- `~/Library/LaunchAgents/local.firstmate.telegram-relay.plist` scans held captain
  questions every 30 seconds. The clock uses the existing captain-hold timestamp:
  no sends before 600 seconds. Resolving/replacing the hold cancels unsent/stale
  questions. Deferred future-date holds are not sent.
- Replies use the existing `fm-inbox.sh note -` durable queue and its normal wake
  into the owning Firstmate home. They do not directly approve, close or merge.
- Question codes persist before sending. Accepted notifications are deduplicated;
  a network timeout/crash after Telegram accepts but before local acknowledgement
  can resend the same code (Bot API has no send idempotency key). Repeated answers
  are deduplicated, including recovery after inbox enqueue but before DB commit.

Every real question must be recorded with `fm-captain-hold.sh`; unrecorded prose
cannot acquire a reliable timer. The old watcher draft is not used. Do not also
send manual timed escalations for relay-owned questions.

## Evidence and rollback

Timer boundary, retries/stable codes, stale replies, restart/deduplication,
unauthorized users/platforms, shell-literal content and the real tasks-axi held
projection are covered by `test_fm_telegram_relay.py`. Busy-gateway interception
is covered by `test_firstmate_plugin.py`. The actual installed Hermes lifecycle
hook -> SSH -> host status path was exercised without a model call; two existing
held questions were accepted by Telegram. No synthetic captain approval was
injected into production to test a reply.

Disable: boot out `local.firstmate.telegram-relay`, disable the Hermes plugin,
remove its hook symlink, then restart Hermes. This does not alter task state or
pipeline custody. Preserve the SQLite ledger if re-enabling, to retain dedupe.
