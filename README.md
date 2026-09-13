# dotfiles

My personal, reproducible nix setup for this Mac: nix-darwin + home-manager +
sops-nix. Clone it on a fresh machine, run one command, get the same system back.

```
switch    # alias for: sudo darwin-rebuild switch --flake ~/dotfiles#main
```

Remember: flakes only see git-tracked files. `git add` new files before switching.

## How secrets work (so I don't have to re-learn this)

`secrets.yaml` is a locked box. The combination (data key) is written on slips
of paper taped to the box in sealed envelopes, one per age key that's allowed in.
An age key is a seal/opener pair: the public half seals, the private half opens.

- `secrets.yaml`   — the box + envelopes. Encrypted. Safe to commit.
- `.sops.yaml`     — the list of who gets an envelope. Public keys only. Safe to commit.
- `~/.config/sops/age/keys.txt` — this Mac's opener. **Never in the repo.**
- Recovery opener  — lives in my password manager, not on any machine.

At `switch` / login, sops-nix opens the box and drops each secret as a plain
file in `~/.config/sops-nix/secrets/`. `.zshrc` `cat`s those into env vars.

Everything in this repo can be public. Whoever clones it gets a welded-shut box.

## Editing secrets

```
sops secrets.yaml                # edits in $EDITOR, re-encrypts on save
sops updatekeys secrets.yaml     # after changing .sops.yaml: re-tape envelopes
```

## New Mac

```
git clone <this repo> ~/dotfiles && cd ~/dotfiles && ./bootstrap.sh
```

It installs nix if missing, sets up this machine's age key, and runs the first
switch. The key: either paste the recovery key from my password manager when
asked (fastest), or let it generate a new one — it then prints the `age1...` and
stops. Add that to `.sops.yaml`, then from something that can already open the
box (old Mac, or `SOPS_AGE_KEY_FILE=recovery.txt`):

```
sops updatekeys secrets.yaml
```

Commit, push, pull on the new Mac, re-run `./bootstrap.sh`. New shell,
`env | grep AWS_` should be populated.

If both the old Mac and the recovery key are gone, the box is gone: rotate every
credential at the provider and start a new `secrets.yaml`.

Homebrew is installed and managed by nix-homebrew. Nothing to install by hand.
If I ever use the Determinate installer instead: `nix.enable = false;` in
`configuration.nix` and drop `nix.extraOptions`.
