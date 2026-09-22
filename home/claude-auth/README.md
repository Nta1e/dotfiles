# Claude interactive authentication

Interactive Claude Code and quota reads use Claude's refreshable Keychain login.
The SOPS `claude_oauth_token` is service-only; Hermes still receives it through its existing env templates.
Do not globally export `CLAUDE_CODE_OAUTH_TOKEN`: setup tokens can lack account/profile scope, mask an interactive login, and leave its expired Keychain credential unused.

`home.nix` clears inherited setup-token overrides in new zsh and bash login shells.
The local `quota-axi` wrapper also clears that override when called by an older terminal server or coordinator, then forwards all arguments and exit status to the npm-installed CLI.
This is credential-source selection, not a quota cache or a fabricated authenticated state.
Explicit setup-token diagnostics can bypass the wrapper via `~/.npm-global/bin/quota-axi`.
Do not use that bypass for routine interactive quota polling.
Existing running Claude processes retain their original environment; no worker restart is required.

## Complete an expired, unrefreshable login

In the user's existing terminal:

```sh
unset CLAUDE_CODE_OAUTH_TOKEN
rehash  # zsh; bash uses hash -r
claude auth login --claudeai
quota-axi --provider claude --full
```

The browser approval must be performed by the user.
`claude auth status` alone is not proof that a token is currently accepted remotely.
Quota endpoint rate limiting can still make a valid login temporarily unmeasurable; do not confuse it with model quota exhaustion.
No inference probe is needed for a working full-scope interactive login.

## Local activation on oldmac, 2026-09-21

- The existing SOPS environment token received HTTP 429 from the usage endpoint and HTTP 403 (missing profile scope) from the profile endpoint.
- quota-axi 0.1.48 chose an expired Keychain failure over that transient environment-token failure, displaying sign-in required.
- Every observed live Claude worker had the same SOPS override, so no worker was using the Keychain credential being repaired.
- `claude doctor` without the override exited successfully but did not renew the credential.
- One isolated native Sonnet request (safe mode, no tools/MCP/browser, no session persistence, USD 0.05 budget) without the override failed before a successful reply: `OAuth session expired and could not be refreshed`.
- A fresh browser login is required; no working quota numbers have yet been verified.
- Two Nix realization attempts stalled fetching the pinned source, so no full system switch was performed.
- Only `.zshrc` and `.profile` were hotfixed by copying the existing generated files and replacing the one token-export line with `unset CLAUDE_CODE_OAUTH_TOKEN`.
- Their live symlinks point to `~/.config/claude-auth/{zshrc,profile}.repaired`; original files and symlink targets are preserved in `~/.config/claude-auth/backup-20260921-154742/`.
- The tracked `home.nix` change supplies the same behavior on the next normal system switch. Home Manager can replace/back up these temporary shell symlinks through its configured backup behavior.
- `~/.local/bin/quota-axi` points to this directory's wrapper, also declared in `home.nix`.
- No credentials were hand-edited/deleted, no secret was rotated by this patch, and MCP credentials were left intact. Claude's own failed refresh may invalidate its expired OAuth record.

Verification:

```sh
python3 home/claude-auth/test_quota_wrapper.py
nix-instantiate --parse home.nix >/dev/null
```

Live zsh and bash login-shell checks confirmed that an inherited dummy override is cleared.
The wrapper reports quota-axi 0.1.48 and auth inspection no longer lists an environment-token source.
