# Krunchix GitHub Actions runners on oldmac, inside colima.
#
# Each slot mirrors the ARC pod that ran on Hetzner: a docker:dind container
# plus an ephemeral actions-runner container sharing its network namespace.
# Jobs therefore get their own dockerd for service containers (Backend's
# Postgres on localhost:5432) without two slots fighting over host ports.
# A slot runs exactly one job, then both containers and their volumes are
# thrown away, so every job starts from a clean runner and an empty dockerd.

org=Krunchix
app_id=5104929
installation_id=165688469
key="$HOME/.config/sops-nix/secrets/ci_github_app_private_key"
label=oldmac-linux
slots=2
runner_image=ghcr.io/actions/actions-runner:latest
dind_image=docker:dind

export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

registration_token() {
  local now header payload sig jwt install_token
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  # iat backdated 60s for clock drift; GitHub caps App JWTs at 10 minutes.
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64url)
  sig=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$key" | b64url)
  jwt="$header.$payload.$sig"
  install_token=$(curl -fsS -X POST \
    -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$installation_id/access_tokens" | jq -er .token) || return 1
  curl -fsS -X POST \
    -H "Authorization: Bearer $install_token" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$org/actions/runners/registration-token" | jq -er .token
}

cleanup_slot() {
  docker rm -f "ci-$1-runner" "ci-$1-dind" >/dev/null 2>&1 || true
  docker volume rm "ci-$1-sock" >/dev/null 2>&1 || true
}

start_dind() {
  local n=$1 _
  # --group=123 is the docker group in the runner image, so the runner user
  # can use the socket. oom-score-adj 500 makes the VM kill CI before Hermes.
  docker run -d --name "ci-$n-dind" --privileged --memory 4g --oom-score-adj 500 \
    -v "ci-$n-sock:/var/run" \
    "$dind_image" dockerd --host=unix:///var/run/docker.sock --group=123 >/dev/null || return 1
  for _ in $(seq 60); do
    docker exec "ci-$n-dind" docker info >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

# The script runs under errexit, so every docker call in the loop must be
# guarded: an unguarded failure (e.g. colima restarting) kills the slot for
# good while the pull loop keeps `wait` alive, and launchd never notices.
run_slot() {
  local n=$1 token
  while true; do
    until docker info >/dev/null 2>&1; do sleep 5; done
    cleanup_slot "$n"
    if ! token=$(registration_token); then
      echo "slot $n: could not get a registration token, retrying in 60s" >&2
      sleep 60
      continue
    fi
    if ! start_dind "$n"; then
      echo "slot $n: dind did not come up, retrying in 30s" >&2
      sleep 30
      continue
    fi
    docker run --rm --name "ci-$n-runner" --network "container:ci-$n-dind" \
      --memory 8g --oom-score-adj 500 \
      -v "ci-$n-sock:/var/run" -e DOCKER_HOST=unix:///var/run/docker.sock \
      "$runner_image" bash -c \
      "./config.sh --unattended --ephemeral --disableupdate --url https://github.com/$org \
         --token $token --name oldmac-$n-\$(date +%s) --labels $label && ./run.sh" \
      || echo "slot $n: runner exited non-zero" >&2
  done
}

until docker info >/dev/null 2>&1; do sleep 5; done
until [ -r "$key" ]; do sleep 30; done

# --disableupdate needs a current image: GitHub refuses runners that fall too
# far behind, so refresh twice a day instead of pulling on every job.
(while true; do
  docker pull -q "$runner_image" >/dev/null 2>&1 || true
  docker pull -q "$dind_image" >/dev/null 2>&1 || true
  sleep 43200
done) &

for n in $(seq 1 "$slots"); do
  run_slot "$n" &
done
wait
