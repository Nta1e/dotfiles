# Hermes: Telegram -> firstmate

Hermes Agent runs as a docker container on the server Mac (upstream does not
support macOS on Intel natively) and is the captain's phone-side liaison. Its
terminal tool reaches the host over ssh and drives firstmate through
`fm-inbox.sh note|status` and the herdr CLI, per `SOUL.md`, the always-loaded system prompt.

```
phone (Telegram) -> hermes gateway (docker, colima) --ssh--> host: fm-inbox.sh / herdr
```

Managed by home.nix on the server host: `launchd.agents.colima`,
`launchd.agents.hermes` (docker-compose on a generated compose file, named
volume `hermes-data`), and the sops template `~/.hermes/env`.

## Secrets (sops secrets.yaml)

- `telegram_bot_token`: from @BotFather `/newbot`
- `telegram_allowed_users`: your numeric Telegram user id (@userinfobot), comma-separated for several
- `hermes_ssh_key`: private ed25519 key whose public half is in the host's `~/.ssh/authorized_keys`
- `claude_oauth_token` (existing): Hermes routes as Claude Code; needs Claude Max with extra usage enabled

## First run on the server

```
switch                       # renders ~/.hermes/env, loads the agents, pulls the image
home/hermes/seed.sh          # ssh key into the volume, terminal.backend=ssh, model
tail -f ~/Library/Logs/hermes.log
```

Then DM the bot. Change the model any time with `docker exec hermes hermes config set model.default <id>`
or `/model` in chat. Update: `docker-compose -f <compose> pull` then
`launchctl kickstart -k gui/$(id -u)/org.nix-community.home.hermes`.
