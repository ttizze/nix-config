{
  description = "ttizze's reproducible macOS and Linux CLI environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

  };

  outputs =
    inputs@{
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      ...
    }:
    let
      username = "tt";
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      overlay = final: _prev: {
        dcg = final.callPackage ./pkgs/dcg.nix { };
      };
      allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ overlay ];
          config.allowUnfreePredicate = allowUnfreePredicate;
        };
      mkLinuxHome =
        system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = { inherit inputs username; };
          modules = [
            ./home/tt/common.nix
            ./home/tt/linux.nix
          ];
        };
    in
    {
      darwinConfigurations.tinoMac-mini = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit
            inputs
            username
            overlay
            allowUnfreePredicate
            ;
        };
        modules = [
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          ./hosts/tinoMac-mini
        ];
      };

      homeConfigurations = {
        "tt@linux-aarch64" = mkLinuxHome "aarch64-linux";
        "tt@linux-x86_64" = mkLinuxHome "x86_64-linux";
      };

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          inherit (pkgs) dcg;
          default = pkgs.dcg;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          dcg = pkgs.dcg;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              jq
              just
              nixfmt-tree
              nvd
              shellcheck
            ];
          };
        }
      );

      templates = rec {
        minimal = {
          path = ./templates/minimal;
          description = "Minimal Nix project with direnv, just, and Agent instructions";
        };
        bun = {
          path = ./templates/bun;
          description = "Bun project with a Nix-pinned runtime";
        };
        node-pnpm = {
          path = ./templates/node-pnpm;
          description = "Node.js and pnpm project with Nix-pinned tools";
        };
        python-uv = {
          path = ./templates/python-uv;
          description = "Python and uv project with Nix owning the interpreter";
        };
        ios = {
          path = ./templates/ios;
          description = "iOS project with XcodeGen and Ruby tooling";
        };
        default = minimal;
      };

      formatter = forAllSystems (system: (mkPkgs system).nixfmt-tree);
    };
}
