# Captain preferences

## Local optimization controls (2026-09-19)
- Firstmate setup is a third-party local tool: no commits, pushes, upstream PRs/issues or publication pipelines for these optimizations. Preserve existing workers and worktrees. Live `data/captain.md` carries newer task-specific rulings; do not overwrite it with this seed.
- Coordinator: Pi `openai-codex/gpt-5.5`, medium reasoning, in the existing session. No Astra/Fable for routine orchestration.
- Mobile per-rule tier ladders: exceptional Fable -> Astra; difficult Opus -> GPT-5.5; routine Sonnet -> GPT Luna. Preserve tool-specific exceptions and capability tiers. Unknown quota is not proven exhaustion: try the configured Claude model once on future dispatches; leave current workers alone. Report the actual sanitized task/model error to the captain before fallback. Distinguish quota/rate-limit from auth/login, access, network and unknown failures. Verified quota failures may use the same-tier GPT fallback with disclosure; authentication/access failures need captain attention, not silent GPT substitution. Do not retry blindly or duplicate a partially started worker. Explicit floors/approval gates still apply. GPT mobile workers need the configured 15% all-model reserve; this cannot fence external clients or existing validators.
- At most 3 active/unknown workers, never a minimum. `fm-spawn.sh` checks local admission under its task-set lock before new spawns; preserve existing jobs/relaunches.
- Before every new task-selection/dispatch decision, verify readiness, merged dependencies and design-system-first priority from tool evidence, then consult `python3 bin/fm-jev-classify.py next_task evidence.json` and `overlap` against active ownership. Consult `intake` on ambiguous new instructions and `failure` on new blockers. Use accepted requirements and bounded current facts, not whole transcripts. Cache unchanged decisions by evidence digest; no model calls for clocks, locks or unchanged state.
- Local no-mistakes Jev integration: native-agent override wrappers add advisory intent preflight/fix triage; a separate read-only observer classifies completed review-round findings. Read `python3 /Users/ntaleshadik/dotfiles/home/no-mistakes/jev-findings.py status <run-id>` before interpreting a gate. No advisory grants approval, edits findings or skips native review/tests/CI. Existing running agents are unchanged.
- Record genuine captain questions with `fm-captain-hold.sh`. A separate local launchd relay owns the 600-second escalation timer and deduplication; resolve the hold when answered locally. Hermes's existing authenticated receiver handles `/fmreply <code> <answer>` and `/fmstatus` without an LLM, even while its agent is busy. Replies go into the current Firstmate home's durable inbox, not directly into approval state. Plain free-text Hermes conversations still use its model. Do not add another Telegram poller or duplicate the relay's timed messages.

## Priorities
- The Krunchix customer mobile app comes first: `Krunchix/krunchix`, path `frontend/apps/mobile` (Expo / React Native). When two tasks compete for attention, quota, or a crewmate slot, the mobile app wins. Register the monorepo as project `krunchix` with posture `no-mistakes-prod-only`.
- Architecture, research, and product-design work goes to Fable at xhigh while Fable quota is present, otherwise to GPT-6 Astra or the latest Opus; `config/crew-dispatch.json` encodes this, keep it that way when curating rules.
- Two subscriptions are available to the crew: Claude (claude harness) and ChatGPT (Pi harness with the `openai-codex/*` provider, ChatGPT login). All GPT and Grok models run through Pi (`openai-codex/...`, `xai/...`); the one exception is image generation, which uses the codex harness because that is a Codex CLI tool. Spread well-defined work onto the OpenAI pool so Claude quota stays free for the hard tasks.
- Prefer quality, simplicity, robustness, and long-term maintainability over development cost when a crewmate has to choose.

## Odoo (Krunchix/odoo, project `odoo`)
- Registered `direct-PR +yolo` on 2026-09-18 at the captain's word: no no-mistakes pipeline. Every change adds tests, the worker runs them locally (`just test <module>`) and pushes only when they pass; firstmate merges the green PR to main itself without asking. Captain's phrasing: "just push to main when tests pass locally".
- Odoo work never goes to Fable; routine Odoo changes are cheap-model work, the dispatch rules draw the line (captain, 2026-09-18).

## Krunchix monorepo (project `krunchix`)
- Every PR goes through no-mistakes, no exceptions for one-line fixes; merge on the captain's approval (yolo off). Captain's ruling in the 2026-09-18 architecture review; registry moved from `no-mistakes-prod-only` to flat `no-mistakes` accordingly.
- Plan of record: data/krunchix-arch-research/report.md (revision 2) with the captain's answers in captain-answers-2026-09-18.md; the backlog lives on the Krunchix org project https://github.com/orgs/Krunchix/projects/1, stages as milestones, one issue per task, worked one at a time in order. Website work is parked.

## Working style
- Report outcomes plainly: PR links, CI state, what was left out and why. No cheerleading.
- Escalate only real decisions. Routine merges of green, in-scope PRs on the mobile app may be proposed, never merged without my explicit "merge it" (yolo stays off).
- For bug fixes, crewmates reproduce end-to-end first, as close to how a user experiences it as possible, before fixing.
- Be picky about UI: pixel-level polish matters on the mobile app; fix clearly-off visuals encountered along the way.
- Fix lint, test failures, and flaky tests encountered along the way, even when unrelated to the task.

## Conventions crewmates must follow
- Commit messages: short, gitmoji-prefixed subject, terse body only when needed. Never add agent trailers (no Co-Authored-By, no Claude-Session, no "Generated with"). No-mistakes correction commits follow the same convention: a concise `🔧 <summary>` subject, never a `no-mistakes(<step>):` prefix.
- PR descriptions are developer-facing release notes: state what changed, why it changed when useful, and how it was verified. Do not address or refer to the captain, include nautical/chat language, or add AI/agent attribution such as "Built with Claude". The no-mistakes pipeline may add its normal review and validation comments separately.
- Never use the em dash "—" in text or code comments; use "-".
- Only comment code when it adds non-obvious value (why, gotcha, invariant).
- Never hand-edit CHANGELOG.md or files marked auto-generated.

## Reporting to the captain (Telegram)
- A note tagged `[via telegram]` came from the captain's phone through Hermes. For the task it becomes, report back with `fm-tg "<text>"` (on PATH; posts to the captain's Telegram as the bot): when the PR is opened or merged (one line + URL), when the task lands on captain hold (one line per open question, or a pointer to the brief), and when it fails or is abandoned (one line, what is needed). One message per event, no progress chatter. Tasks that did not come via Telegram stay in the pane unless the captain asks.
- "What is pending / what is done" asked from Telegram is answered by Hermes from `fm-inbox.sh status`; firstmate does not need to send digests.

## Planning into a board (GitHub Projects)
- Board: the Krunchix org project #1 "Krunchix", https://github.com/orgs/Krunchix/projects/1 (`gh project item-add 1 --owner Krunchix --url <issue url>`; statuses Todo / In Progress / Done).
- The moment a plan is accepted (the captain answers the open calls or says go), segment it into small, independently testable increments before any code: one GitHub issue per increment in the repo it touches, each with the outcome, the test that proves it, and its dependencies; add every issue to the board in delivery order. The backlog entry for each increment references its issue URL.
- Work increments one at a time in order: one PR per issue ("Closes #n"), board status Todo -> In progress -> Done, ship each before starting the next unless the captain says to parallelise. A blocked increment stays In progress with the blocker written on the issue.
