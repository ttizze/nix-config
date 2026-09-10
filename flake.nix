{
  description = "ttizze's reproducible macOS and Linux CLI environment";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs.git?ref=nixpkgs-unstable";

    nixpkgs-server.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-server";
    };

    agent-config = {
      url = "git+ssh://git@github.com/ttizze/agent-config.git?ref=main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "git+https://github.com/nix-darwin/nix-darwin.git?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "git+https://github.com/nix-community/home-manager.git?ref=master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "git+https://github.com/zhaofengli-wip/nix-homebrew.git?ref=main";

    homebrew-core = {
      url = "git+https://github.com/Homebrew/homebrew-core.git?ref=main";
      flake = false;
    };

    homebrew-cask = {
      url = "git+https://github.com/Homebrew/homebrew-cask.git?ref=main";
      flake = false;
    };

    homebrew-aerospace = {
      url = "git+https://github.com/nikitabobko/homebrew-tap.git?ref=main";
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
        circleback-cli = final.callPackage ./pkgs/circleback-cli { };
        codex-acp = final.callPackage ./pkgs/codex-acp { };
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
      nixosConfigurations.ci-1 = inputs.nixpkgs-server.lib.nixosSystem {
        modules = [
          inputs.disko.nixosModules.disko
          ./hosts/ci-1
        ];
      };

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
          inherit (pkgs)
            circleback-cli
            claude-agent-acp
            codex-acp
            dcg
            ;
          default = pkgs.dcg;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          circleback-cli = pkgs.circleback-cli;
          claude-agent-acp = pkgs.claude-agent-acp;
          codex-acp = pkgs.codex-acp;
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
              hcloud
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
