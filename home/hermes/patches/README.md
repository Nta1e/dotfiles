# Local patches to the Hermes image

Bind-mounted over the image's plugin directories by the compose file in
home.nix. Each directory is a verbatim copy of the upstream plugin at the image
version noted below plus a marked `# Krunchix patch` block; re-copy and re-apply
when the image moves.

- `mattermost/` (Hermes v0.21.3, upstream f5d19261): follow-up replies in a
  thread the bot is already part of (it was @mentioned there, or it replied
  there) are answered without a fresh @mention, the way the Slack adapter's
  mentioned-threads set works. Worth sending upstream.
