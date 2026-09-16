# Captain preferences

## Priorities
- The Krunchix customer mobile app comes first: `Krunchix/krunchix`, path `frontend/apps/mobile` (Expo / React Native). When two tasks compete for attention, quota, or a crewmate slot, the mobile app wins. Register the monorepo as project `krunchix` with posture `no-mistakes-prod-only`.
- Architecture, research, and product-design work goes to Fable at xhigh while Fable quota is present, otherwise to GPT-6 Astra or the latest Opus; `config/crew-dispatch.json` encodes this, keep it that way when curating rules.
- Two subscriptions are available to the crew: Claude (claude harness) and ChatGPT (Pi harness with the `openai-codex/*` provider, ChatGPT login). All GPT and Grok models run through Pi (`openai-codex/...`, `xai/...`); the one exception is image generation, which uses the codex harness because that is a Codex CLI tool. Spread well-defined work onto the OpenAI pool so Claude quota stays free for the hard tasks.
- Prefer quality, simplicity, robustness, and long-term maintainability over development cost when a crewmate has to choose.

## Working style
- Report outcomes plainly: PR links, CI state, what was left out and why. No cheerleading.
- Escalate only real decisions. Routine merges of green, in-scope PRs on the mobile app may be proposed, never merged without my explicit "merge it" (yolo stays off).
- For bug fixes, crewmates reproduce end-to-end first, as close to how a user experiences it as possible, before fixing.
- Be picky about UI: pixel-level polish matters on the mobile app; fix clearly-off visuals encountered along the way.
- Fix lint, test failures, and flaky tests encountered along the way, even when unrelated to the task.

## Conventions crewmates must follow
- Commit messages: short, gitmoji-prefixed subject, terse body only when needed. Never add agent trailers (no Co-Authored-By, no Claude-Session, no "Generated with").
- Never use the em dash "—" in text or code comments; use "-".
- Only comment code when it adds non-obvious value (why, gotcha, invariant).
- Never hand-edit CHANGELOG.md or files marked auto-generated.
