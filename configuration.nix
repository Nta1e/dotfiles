{ pkgs, config, lib, self, ... }:
{

  # Enable experimental nix command and flakes
  # nix.package = pkgs.nixUnstable;
  nix.extraOptions = ''
    auto-optimise-store = true
    experimental-features = nix-command flakes
  '';

  # Create /etc/bashrc that loads the nix-darwin environment.
  programs.zsh.enable = true;

  # Apps
  environment.systemPackages = [];

  programs.nix-index.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    recursive
    nerd-fonts.jetbrains-mono
   ];

  homebrew = {
   enable = true;
   taps = [
     "my-monkeys/tap"
     "android-platform-tools"
   ];
   casks = [
     "wezterm"
     "temurin@17"
     "claude-code"
     "tailscale-app"
     "my-monkeys/tap/opensuperwhisper"
   ];
   # herdr comes from pkgs/herdr: Homebrew ships no Intel bottle for it, and
   # neither for mole, which the server does not need anyway.
   brews = lib.optionals pkgs.stdenv.hostPlatform.isAarch64 [
     "mole"
   ];
   onActivation.cleanup = "zap";
  };

  # Make casks(GUI apps) installed via cask findable in spotlight search
  system.activationScripts.applications.text = let

  env = pkgs.buildEnv {
    name = "system-applications";
    paths = config.environment.systemPackages;
    pathsToLink = ["/Applications"];
  };

  in
    pkgs.lib.mkForce ''
      # Set up applications.
      echo "setting up /Applications..." >&2
      rm -rf /Applications/Nix\ Apps
      mkdir -p /Applications/Nix\ Apps
      find ${env}/Applications -maxdepth 1 -type l -exec readlink '{}' + |
      while read -r src; do
      app_name=$(basename "$src")
      echo "copying $src" >&2
      ${pkgs.mkalias}/bin/mkalias "$src" "/Applications/Nix Apps/$app_name"
      done
      '';
 
  # The headless Intel Mac's always-on services, as system daemons running as
  # the user: they start at boot and survive a logout or a WindowServer crash,
  # which a per-user LaunchAgent does not (2026-09-18: both relays went down
  # with the GUI session). The scripts live in the user profile (home.nix).
  launchd.daemons = let
    user = "ntaleshadik";
    home = "/Users/${user}";
    bin = "/etc/profiles/per-user/${user}/bin";
    daemon = name: log: {
      serviceConfig = {
        ProgramArguments = [ "${bin}/${name}" ];
        UserName = user;
        GroupName = "staff";
        WorkingDirectory = home;
        EnvironmentVariables = {
          HOME = home;
          PATH = "${bin}:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        };
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "${home}/Library/Logs/${log}";
        StandardErrorPath = "${home}/Library/Logs/${log}";
      };
    };
  in lib.optionalAttrs pkgs.stdenv.hostPlatform.isx86_64 {
    colima = daemon "colima-daemon" "colima.log";
    hermes = daemon "hermes-gateway" "hermes.log";
  };

  # Remote Login: keys only. Make sure `ssh <host>` works without a password
  # before switching this in, or the next login needs the screen.
  environment.etc."ssh/sshd_config.d/200-keys-only.conf".text = ''
    PasswordAuthentication no
    KbdInteractiveAuthentication no
  '';

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;
  
  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
  system.primaryUser = "ntaleshadik";
  nixpkgs.config.allowUnfree = true;
}
