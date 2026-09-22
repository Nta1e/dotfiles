#!/usr/bin/env bash
# One-time ChatGPT/Codex OAuth login for the Hermes Docker volume.
# Choose "ChatGPT or Codex Subscription" in the model picker.
set -euo pipefail

composefile=$(grep -o '/nix/store/[^ ]*hermes-compose.yaml' "$(command -v hermes-gateway)" | head -n 1)
if [[ -z "${composefile}" || ! -f "${composefile}" ]]; then
  echo "Could not locate Hermes' generated compose file via hermes-gateway." >&2
  exit 1
fi

exec docker-compose -f "${composefile}" run --rm --entrypoint hermes hermes model
