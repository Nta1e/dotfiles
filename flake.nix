{
  description = "Ntale's darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    home-manager.url = "github:nix-community/home-manager/master";
    sops-nix.url = "github:Mic92/sops-nix";
    sqlit.url = "github:Maxteabag/sqlit";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # Agent skills and CLIs: plain repos pinned in flake.lock (`nix flake update lavish-axi`)
    lavish-axi = { url = "github:kunchenguid/lavish-axi"; flake = false; };
    quota-axi = { url = "github:kunchenguid/quota-axi"; flake = false; };
    gh-axi = { url = "github:kunchenguid/gh-axi"; flake = false; };
    figma-axi = { url = "github:ardaatahan/figma-axi"; flake = false; };
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs,  nix-homebrew, home-manager, sops-nix, ... }:
  let
    # One configuration per Mac architecture, named after the nix system so
    # `switch` and bootstrap.sh can pick it from `uname -m`:
    # $ darwin-rebuild build --flake .#aarch64-darwin
    mkDarwin = system: nix-darwin.lib.darwinSystem {
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
        home-manager.darwinModules.home-manager
        {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = { inherit inputs; };
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
