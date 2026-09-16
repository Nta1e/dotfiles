{
  description = "Ntale's darwin system flake";

  inputs = {
    # nixpkgs-unstable, not master: it is what Hydra builds, so packages come
    # from the binary cache instead of compiling here.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    # Without this nix-darwin evaluates against its own nixpkgs pin and the
    # input above only supplies `lib`.
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    home-manager.url = "github:nix-community/home-manager/master";
    sops-nix.url = "github:Mic92/sops-nix";
    # nixpkgs-unstable dropped x86_64-darwin in 26.11. 26.05 is the last branch
    # with it, so the Intel Mac gets the matching release branches (frozen, cached).
    nixpkgs-intel.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin-intel.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin-intel.inputs.nixpkgs.follows = "nixpkgs-intel";
    home-manager-intel.url = "github:nix-community/home-manager/release-26.05";
    home-manager-intel.inputs.nixpkgs.follows = "nixpkgs-intel";
    sqlit.url = "github:Maxteabag/sqlit";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Agent skills and CLIs: plain repos pinned in flake.lock (`nix flake update lavish-axi`)
    lavish-axi = { url = "github:kunchenguid/lavish-axi"; flake = false; };
    quota-axi = { url = "github:kunchenguid/quota-axi"; flake = false; };
    gh-axi = { url = "github:kunchenguid/gh-axi"; flake = false; };
    figma-axi = { url = "github:ardaatahan/figma-axi"; flake = false; };
    # firstmate's worktree provider
    treehouse = { url = "github:kunchenguid/treehouse"; flake = false; };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs,  nix-homebrew, home-manager, sops-nix, ... }:
  let
    # One configuration per Mac architecture, named after the nix system so
    # `switch` and bootstrap.sh can pick it from `uname -m`:
    # $ darwin-rebuild build --flake .#aarch64-darwin
    mkDarwin = system: let
      intel = system == "x86_64-darwin";
      darwin = if intel then inputs.nix-darwin-intel else nix-darwin;
      hm = if intel then inputs.home-manager-intel else home-manager;
    in darwin.lib.darwinSystem {
      modules = [
        { nixpkgs.hostPlatform = system; }
        ./configuration.nix
        { _module.args.self = self; }
        nix-homebrew.darwinModules.nix-homebrew
        ({ pkgs, ... }: {
           nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;
            # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
            enableRosetta = pkgs.stdenv.hostPlatform.isAarch64;
            # User owning the Homebrew prefix
            user = "ntaleshadik";

          };
        })
        hm.darwinModules.home-manager
        {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            # The Intel Mac is the headless agent box; home.nix skips
            # workstation-only tools there.
            home-manager.extraSpecialArgs = { inherit inputs; server = intel; };
            home-manager.users.ntaleshadik = ./home.nix;
            users.users.ntaleshadik.home = "/Users/ntaleshadik";
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
        }
      ];
    };
  in
  {
    darwinConfigurations = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] mkDarwin;
  };
}
