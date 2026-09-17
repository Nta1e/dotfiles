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

echo "==> config.yaml"
run hermes config set terminal.backend ssh
run hermes config set model.provider anthropic
run hermes config set model.default claude-haiku-4-5

echo "==> restart gateway"
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.hermes"
echo "done; tail -f ~/Library/Logs/hermes.log"
