# Hermes `ops` profile: Mattermost front door for the directors

Hermes profile `ops` (`/opt/data/profiles/ops` in the volume), served by the
same gateway as the Telegram liaison (`gateway.multiplex_profiles`). A named
profile reads secrets only from its own `.env`, which seed.sh copies in from
the sops-rendered `~/.hermes/env-ops`; re-run seed.sh when those change.
Scope: Odoo operations only, answers in threads, two allowed users. `SOUL.md`
here is its always-loaded prompt.

```
Mattermost -> hermes gateway (docker, profile ops) --ssh--> host: psql (read-only) / kx (writes via odoo shell)
```

Writes go through `kx` (`~/workspace/odoo/tools/kx`, on PATH via home.nix),
never ad-hoc SQL, and the SOUL makes the bot dry-run and ask first.

## Secrets (sops secrets.yaml)

- `mattermost_bot_token`: the `mise` bot's token (the same one Odoo posts
  with; it already sits in the channels that matter, and the gateway ignores
  the bot's own posts, so Odoo's alerts never trigger it). Also read by
  `kx mm dm` on the host from the sops secret file.
- `mattermost_ops_users`: `54y6m33eyb8zirqy8o3agsnw8r,6kgzhw37ujr6ug7aznjcj3fyqh`
  (Ntale, Sophie).

`MATTERMOST_URL`, thread mode and mention gating are plain config in the
`hermes-ops.env` template in home.nix.

## First run

```
switch                       # renders ~/.hermes/env-ops, creates ~/.hermes/ops-documents
home/hermes/seed.sh          # creates the profile, links SOUL + document cache, sets model
```

Then DM the bot, or `@mise` it in a channel it is in.

## Attachments

The adapter saves posted files under the profile's `cache/documents`; seed.sh
makes that a symlink to `/opt/host-documents`, which is `~/.hermes/ops-documents`
on the host, so `kx equity import` can read the PDF the agent was handed.
