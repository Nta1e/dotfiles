#!/usr/bin/env bash
# One-time seed of the hermes docker volume on the server host: ssh key for
# the terminal backend, and the config.yaml settings that have no env var.
# Idempotent. Run after `switch` has rendered ~/.hermes/env and the sops key.
set -euo pipefail

export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
# The compose file is a store path baked into the launchd script; read it from
# the installed plist rather than duplicating it here.
script=$(plutil -extract ProgramArguments.2 raw -o - ~/Library/LaunchAgents/org.nix-community.home.hermes.plist | grep -o '/nix/store/[^ ]*hermes-gateway')
composefile=$(grep -o '/nix/store/[^ ]*hermes-compose.yaml' "$script")
run() { docker-compose -f "$composefile" run --rm -T --entrypoint "$1" hermes "${@:2}"; }

echo "==> ssh key into the volume"
# --entrypoint runs as root; the gateway runs as `hermes`, so chown
run sh -c 'mkdir -p /opt/data/ssh && cat > /opt/data/ssh/id_ed25519 && chmod 600 /opt/data/ssh/id_ed25519 && chown -R hermes:hermes /opt/data/ssh' \
  < "$HOME/.config/sops-nix/secrets/hermes_ssh_key"

echo "==> SOUL.md -> dotfiles (always-loaded system prompt)"
run sh -c 'ln -sfn /opt/dotfiles-hermes/SOUL.md /opt/data/SOUL.md'

echo "==> config.yaml"
run hermes config set terminal.backend ssh
run hermes config set model.provider anthropic
run hermes config set model.default claude-haiku-4-5
# a lost agent stops after this many tool calls instead of the default 500
run hermes config set agent.max_turns 30

echo "==> ops profile (Mattermost)"
run sh -c 'hermes profile list 2>/dev/null | grep -q "^ *ops\b" || hermes profile create --no-alias ops'
ops() { run hermes -p ops "$@"; }
run sh -c 'ln -sfn /opt/dotfiles-hermes/ops/SOUL.md /opt/data/profiles/ops/SOUL.md'
# A named profile only reads its own .env, never the container env: that is
# what keeps the Telegram token out of the ops bot and vice versa.
run sh -c 'cat > /opt/data/profiles/ops/.env && chmod 600 /opt/data/profiles/ops/.env' < "$HOME/.hermes/env-ops"
# Attachments: the profile's document cache points at the host-mounted dir,
# so a PDF a captain posts is readable by kx on the host (~/.hermes/ops-documents).
run sh -c 'mkdir -p /opt/data/profiles/ops/cache && rm -rf /opt/data/profiles/ops/cache/documents && ln -sfn /opt/host-documents /opt/data/profiles/ops/cache/documents'
ops config set terminal.backend ssh
ops config set model.provider anthropic
# Sonnet for the money work; the Telegram liaison stays on Haiku.
ops config set model.default claude-sonnet-5
ops config set agent.max_turns 40
# No "terminal..." bubbles in the thread; the persona narrates instead.
ops config set display.platforms.mattermost.tool_progress off
# One gateway process serves every profile.
run hermes config set gateway.multiplex_profiles true
# --entrypoint runs as root; the gateway runs as `hermes` (skills/ too: the
# image copies its bundled skills there at boot and warns if it cannot)
run sh -c 'chown -R hermes:hermes /opt/data/profiles /opt/data/skills'

echo "==> restart gateway"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.hermes"
echo "done; tail -f ~/Library/Logs/hermes.log"
