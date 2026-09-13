# global agent instructions

- Never use the em dash "—". Use plain dash "-" instead
- When writing commit messages, NEVER auto-add your agent name as co-author
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated
- When making technical decisions, do not give much weight to development cost.
  Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- For one-off or infrequent operational work, start with the simplest direct end-to-end path. Do not build wrappers, control planes, policy layers, custom verifiers, or automation unless the direct path exposes a concrete blocker or repeated need that justifies the added machinery.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible.
  This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection.
  If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness.
  If you see one, even if it is not caused by what you are working on right now, still get it fixed.
- Before using "dynamic workflows", "ultra code" or any harness feature that immediately spawns a large swarm of subagents, always explain the tradeoffs and ask the user for explicit approval.

# Comments

Only comment when it adds non-obvious value (why, gotcha, invariant). Do NOT
narrate what the code already says or add ceremonial headers. Prefer no comment
over an obvious one. Match the file's existing comment density.

# Commit messages

Short and to the point, gitmoji-prefixed. A concise subject line; add a body
only when it genuinely needs explaining, and keep it terse. No wordy
multi-paragraph essays.

# Auto-approved safe commands

Read-only shell commands (cat, head, tail, grep/rg, ls, tree, find, wc, echo,
printf, sort, uniq, cut, tr, column, basename, dirname, realpath, which, file,
stat, diff, cd, pwd, and read-only git: status/log/diff/show/branch/remote/
blame/ls-files/stash-list) are pre-authorized in permission settings — they run
without a prompt. When you run one of these under the standing auto-approval,
begin its Bash `description` with `***` so I can see it happened at a glance.
Anything that writes, deletes, deploys, or runs arbitrary code (rm, mv, cp,
sed -i, python/node, docker, kubectl, helm, just, git add/commit/push, output
redirection) is NOT auto-approved — ask as usual.
