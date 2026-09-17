# Hermes `ops` profile: Mattermost front door for the directors

Second gateway on the server Mac, same image and volume as the Telegram
liaison, running as Hermes profile `ops` (`HERMES_HOME=/opt/data/profiles/ops`)
in its own container `hermes-ops`. Scope: Odoo operations only, answers in
threads, two allowed users. `SOUL.md` here is its always-loaded prompt.

```
Mattermost -> hermes-ops (docker) --ssh--> host: psql (read-only) / kx (writes via odoo shell)
```

Writes go through `kx` (`~/workspace/odoo/tools/kx`, on PATH via home.nix),
never ad-hoc SQL, and the SOUL makes the bot dry-run and ask first.

## Secrets (sops secrets.yaml)

- `mattermost_bot_token`: System Console -> Integrations -> Bot Accounts, a bot
  with `post:all`; invite it to the channels it should answer in.
- `mattermost_ops_users`: the two directors' user ids, comma-separated
  (`GET /api/v4/users/username/<name>`).

`MATTERMOST_URL`, thread mode and mention gating are plain config in the
`hermes-ops.env` template in home.nix.

## First run

```
switch                       # renders ~/.hermes/env-ops, creates ~/.hermes/ops-documents
home/hermes/seed.sh          # creates the profile, links SOUL + document cache, sets model
```

Then fill in the three ids in `SOUL.md` (directors-only channel, the two DM
channel ids: `POST /api/v4/channels/direct [bot_id, user_id]`) and DM the bot.

## Attachments

The adapter saves posted files under the profile's `cache/documents`; seed.sh
makes that a symlink to `/opt/host-documents`, which is `~/.hermes/ops-documents`
on the host, so `kx equity import` can read the PDF the agent was handed.
