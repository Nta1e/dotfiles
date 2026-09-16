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
   ];
   casks = [
     "wezterm"
     "claude-code"
     "tailscale-app"
     "my-monkeys/tap/opensuperwhisper"
   ];
   # herdr comes from pkgs/herdr; brew has no bottles for the Intel Mac's macOS
   brews = [
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
 
  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = true;
  
  system.configurationRevision = self.rev or self.dirtyRev or null;
  system.stateVersion = 6;
  system.primaryUser = "ntaleshadik";
  nixpkgs.config.allowUnfree = true;
}
