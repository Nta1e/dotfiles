#!/usr/bin/env bash
# One-time ChatGPT/Codex OAuth login for Hermes' Mattermost (ops) profile.
# Hermes profiles keep independent OAuth credentials; choose gpt-5.5 when asked.
set -euo pipefail

composefile=$(grep -o '/nix/store/[^ ]*hermes-compose.yaml' "$(command -v hermes-gateway)" | head -n 1)
if [[ -z "${composefile}" || ! -f "${composefile}" ]]; then
  echo "Could not locate Hermes' generated compose file via hermes-gateway." >&2
  exit 1
fi

exec docker-compose -f "${composefile}" run --rm --entrypoint hermes hermes -p ops model
