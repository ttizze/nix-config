#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix eval --raw .#packages.aarch64-darwin.dcg.version | grep -qx '0.6.5'
nix eval --raw .#darwinConfigurations.tinoMac-mini.config.nixpkgs.hostPlatform.system | grep -qx 'aarch64-darwin'
nix eval --raw '.#homeConfigurations."tt@linux-aarch64".pkgs.stdenv.hostPlatform.system' | grep -qx 'aarch64-linux'
nix eval --raw '.#homeConfigurations."tt@linux-x86_64".pkgs.stdenv.hostPlatform.system' | grep -qx 'x86_64-linux'
