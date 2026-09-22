# Local Jev integration

Local-only installation; no no-mistakes source patch, rebuild or daemon restart.

- `~/.no-mistakes/config.yaml` uses supported `agent_path_override` entries for
  Claude and Pi. `~/.local/bin/nm-jev-{claude,pi}` call `jev-agent.py`, then `exec`
  the original harness with unchanged arguments/output/exit status.
- Explicit/inferred intent markers in native review prompts trigger bounded Jev
  intent preflight; prompts carrying findings trigger advisory fix triage. Missing
  intent skips prompt preflight rather than inventing requirements. The original
  prompt and all gate instructions remain intact.
- `local.no-mistakes.jev-findings` is a launchd job, every 30 seconds. It reads
  completed review rounds from the installed daemon's SQLite database in **read-only
  mode**, including ask-user findings, and produces per-finding advisory artifacts.
  It never submits decisions or changes pipeline records. At most four findings per
  tick, bounded API timeout, at most three attempts on unavailability.
- `python3 jev-findings.py status <run-id>` reads artifacts. Decisions and hashes
  live under `~/.no-mistakes/jev-{advisories,findings}`. Raw diffs/prompts are not
  retained in those artifacts. Relevant bounded intent/diff/finding excerpts are
  sent to the configured Jev API, never the entire chat transcript.
- Confidence/typed-response validation is owned by Firstmate's local
  `bin/fm-jev-classify.py`. Unavailable/uncertain results have no approval authority.
  Native review, tests, lint, docs, push/PR policy, CI and captain gates still apply.
- Existing native-agent processes are unchanged. Fresh runs pick up the wrapper
  configuration without restarting or cancelling the daemon. Other harnesses or
  explicit per-repository path overrides are not intercepted.

## Validation

`python3 test_jev_agent.py` and `python3 test_jev_findings.py` test prompt
preservation, native argv/stdout/exit semantics, malformed advisory handling,
read-only round observation and deduplication. A live historical review finding
was classified through Jev without restarting/replaying/publishing its pipeline.
`no-mistakes doctor` passes; both wrapped binaries answer `--version` normally.
This is integration evidence, not a measured accuracy claim about Jev.

## Disable

1. Remove only the two local `agent_path_override` entries from the global config
   (pre-install backup: `config.pre-jev-20260919.yaml`; preserve later edits).
2. `launchctl bootout gui/$(id -u)/local.no-mistakes.jev-findings`.
3. Keep existing pipeline custody and validation requirements unchanged.
