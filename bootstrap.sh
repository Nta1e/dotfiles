#!/usr/bin/env bash
# Fresh Mac -> this nix-darwin config. Run once; use `switch` after.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KEY=~/.config/sops/age/keys.txt

echo "==> nix"
if ! command -v nix >/dev/null; then
  sh <(curl -L https://nixos.org/nix/install) --daemon --yes
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
NIX="$(command -v nix)"
nix() { "$NIX" --extra-experimental-features 'nix-command flakes' "$@"; }

echo "==> age key"
if [ ! -f "$KEY" ]; then
  mkdir -p "$(dirname "$KEY")"
  read -r -p "    Paste an existing AGE-SECRET-KEY (or press enter to generate a new one): " SECRET
  if [ -n "$SECRET" ]; then
    printf '%s\n' "$SECRET" > "$KEY"
  else
    nix shell nixpkgs#age -c age-keygen -o "$KEY"
  fi
  chmod 600 "$KEY"
fi
PUB="$(nix shell nixpkgs#age -c age-keygen -y "$KEY")"

# sops-nix decrypts during activation, so the key has to be on the guest list
# before the first switch or activation dies halfway.
if ! grep -q "$PUB" "$DIR/secrets.yaml"; then
  cat >&2 <<MSG
    This machine's key isn't a recipient of secrets.yaml yet:

      $PUB

    On a machine that can decrypt (or with the recovery key from the password manager):
      1. add the key above to .sops.yaml (under keys: and key_groups)
      2. sops updatekeys secrets.yaml
      3. commit, push; then pull here and re-run ./bootstrap.sh
MSG
  exit 1
fi

echo "==> switch"
case "$(uname -m)" in
  arm64)  SYSTEM=aarch64-darwin ;;
  x86_64) echo "nixpkgs no longer supports Intel macOS; run Linux on this machine instead" >&2; exit 1 ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac
[ "$DIR" = "$HOME/dotfiles" ] || echo "    warning: repo is not at ~/dotfiles; the 'switch' alias expects it there"
if [ -n "$(git -C "$DIR" ls-files --others --exclude-standard)" ]; then
  echo "    flakes ignore untracked files, staging them"
  git -C "$DIR" add -A
fi
# sudo drops /nix from PATH, hence $NIX
sudo "$NIX" --extra-experimental-features 'nix-command flakes' \
  run nix-darwin/master#darwin-rebuild -- switch --flake "$DIR#$SYSTEM"

echo "==> done. open a new shell."
