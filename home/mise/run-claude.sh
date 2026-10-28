#!/usr/bin/env bash
# The mise session itself, run inside tmux by mise-session.sh.
set -uo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/workspace/odoo/tools/kx:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export KUBECONFIG="$HOME/.kube/configs/kx-hcloud.yaml"
export TZ=Africa/Kampala

flags=(--model claude-opus-5-5 --dangerously-load-development-channels server:mattermost)
# Resume the running conversation so context survives restarts. Checked up front:
# a failed --continue would show the dev-channel dialog a second time.
transcripts="$HOME/.claude/projects/$(pwd | tr '/.' '--')"
if compgen -G "$transcripts/*.jsonl" >/dev/null; then flags+=(--continue); fi
exec claude "${flags[@]}"
