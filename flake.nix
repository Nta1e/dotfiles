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
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs,  nix-homebrew, home-manager, sops-nix, sqlit }:
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#main
    darwinConfigurations."main" = nix-darwin.lib.darwinSystem {
      modules = [ 
        ./configuration.nix
        { _module.args.self = self; }
        nix-homebrew.darwinModules.nix-homebrew
        {
           nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;
            # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
            enableRosetta = true;
            # User owning the Homebrew prefix
            user = "ntaleshadik";

          };
        }
        home-manager.darwinModules.home-manager
        {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = { inherit sqlit; };
            home-manager.users.ntaleshadik = ./home.nix;
            users.users.ntaleshadik.home = "/Users/ntaleshadik";
            home-manager.sharedModules = [
              sops-nix.homeManagerModules.sops
            ];
        }
      ];
    };
  };
}
