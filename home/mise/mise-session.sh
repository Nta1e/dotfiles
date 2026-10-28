#!/usr/bin/env bash
# launchd entrypoint (KeepAlive): keep the mise session running in a herdr pane.
# Checks every 30s and does nothing while the `mise` agent is alive.
set -uo pipefail
export PATH="/etc/profiles/per-user/$USER/bin:/usr/local/bin:/usr/bin:/bin"
DIR="$(cd "$(dirname "$0")" && pwd)"

start() {
  local ws pane
  ws="$(herdr workspace list | jq -r '.result.workspaces[] | select(.label == "mise") | .workspace_id' | head -1)"
  if [ -n "$ws" ]; then
    pane="$(herdr pane list --workspace "$ws" | jq -r '.result.panes[0].pane_id')"
  else
    pane="$(herdr workspace create --cwd "$DIR" --label mise --no-focus | jq -r '.result.root_pane.pane_id')"
  fi
  echo "$(date '+%F %T') starting mise in $pane"
  herdr pane run "$pane" "$DIR/run-claude.sh" >/dev/null

  # --dangerously-load-development-channels asks for confirmation on every start.
  # Accept only that dialog, and only once the dev option is the highlighted one.
  if herdr pane wait-output "$pane" --match 'I am using this for local development' --timeout 60000 >/dev/null; then
    for _ in 1 2 3; do
      herdr pane read "$pane" | grep -q '❯.*I am using this for local development' && break
      herdr pane send-keys "$pane" down >/dev/null
      sleep 1
    done
    herdr pane send-keys "$pane" enter >/dev/null
  fi
  herdr pane wait-output "$pane" --match 'Channels (experimental)' --timeout 60000 >/dev/null \
    && herdr agent rename "$pane" mise >/dev/null \
    && echo "$(date '+%F %T') mise is up"
}

while true; do
  herdr agent get mise >/dev/null 2>&1 || start
  sleep 30
done
