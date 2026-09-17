#!/bin/sh
# Hermes HERMES_LOCAL_STT_COMMAND: transcribe on the host with whisper.cpp
# (`hermes-stt` from home.nix; the container has no STT engine). Hermes hands
# us a wav and reads back any *.txt in the output dir. Runs with a scrubbed
# env, so everything ssh needs is spelled out.
#   $1 input wav   $2 output dir
set -eu
host=ntaleshadik@host.docker.internal
opts="-i /opt/data/ssh/id_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/opt/data/ssh/known_hosts"
remote="/tmp/hermes-stt-$$.wav"
scp -q $opts "$1" "$host:$remote"
ssh $opts "$host" "hermes-stt $remote; rm -f $remote" | sed 's/^ *//' > "$2/transcript.txt"
