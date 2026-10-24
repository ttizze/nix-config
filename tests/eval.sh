#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix eval --raw .#packages.aarch64-darwin.dcg.version | grep -qx '0.14.4'
nix eval --raw .#packages.aarch64-darwin.circleback-cli.version | grep -qx '0.3.4'
nix eval --raw .#packages.aarch64-darwin.claude-agent-acp.version | grep -qx '0.75.1'
nix eval --raw .#packages.aarch64-darwin.codex-acp.version | grep -qx '1.12.0'
nix eval --json .#packages.aarch64-darwin --apply 'packages: builtins.attrNames packages' |
  jq -e 'index("codex-app-list-fix") == null' >/dev/null
nix eval --raw .#darwinConfigurations.tinoMac-mini.config.nixpkgs.hostPlatform.system | grep -qx 'aarch64-darwin'
nix eval --raw '.#homeConfigurations."tt@linux-aarch64".pkgs.stdenv.hostPlatform.system' | grep -qx 'aarch64-linux'
nix eval --raw '.#homeConfigurations."tt@linux-x86_64".pkgs.stdenv.hostPlatform.system' | grep -qx 'x86_64-linux'
