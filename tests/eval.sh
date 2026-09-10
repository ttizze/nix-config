#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix eval --raw .#packages.aarch64-darwin.dcg.version | grep -qx '0.14.2'
nix eval --raw .#packages.aarch64-darwin.circleback-cli.version | grep -qx '0.3.1'
nix eval --raw .#packages.aarch64-darwin.claude-agent-acp.version | grep -qx '0.75.1'
nix eval --raw .#packages.aarch64-darwin.codex-acp.version | grep -qx '1.11.0'
nix eval --json .#packages.aarch64-darwin --apply 'packages: builtins.attrNames packages' |
  jq -e 'index("codex-app-list-fix") == null' >/dev/null
nix eval --raw .#darwinConfigurations.tinoMac-mini.config.nixpkgs.hostPlatform.system | grep -qx 'aarch64-darwin'
nix eval --raw '.#homeConfigurations."tt@linux-aarch64".pkgs.stdenv.hostPlatform.system' | grep -qx 'aarch64-linux'
nix eval --raw '.#homeConfigurations."tt@linux-x86_64".pkgs.stdenv.hostPlatform.system' | grep -qx 'x86_64-linux'

ci_config='.#nixosConfigurations.ci-1.config'
nix eval --raw "$ci_config.nixpkgs.hostPlatform.system" | grep -qx 'x86_64-linux'
nix eval --json "$ci_config.boot.binfmt.emulatedSystems" |
  jq -e 'index("aarch64-linux") != null' >/dev/null
nix eval --json "$ci_config" --apply '
  config: builtins.mapAttrs (_: runner: {
    inherit (runner) user workDir url;
    groups = (builtins.getAttr runner.user config.users.users).extraGroups;
  }) config.services.github-runners
' | jq -e '
  keys == ["agent-config", "nix-config", "remote-agent", "tsurumi"] and
  ([.[].user] | unique | length) == 4 and
  ([.[].workDir] | unique | length) == 4 and
  all(.[]; .user != "root") and
  (.["agent-config"].groups | index("docker") == null) and
  (.["nix-config"].groups | index("docker") == null) and
  (.["remote-agent"].groups | index("docker") == null) and
  (.["tsurumi"].groups | index("docker") != null) and
  .["agent-config"].url == "https://github.com/ttizze/agent-config" and
  .["nix-config"].url == "https://github.com/ttizze/nix-config" and
  .["remote-agent"].url == "https://github.com/ttizze/remote-agent" and
  .["tsurumi"].url == "https://github.com/ttizze/cinema-maker"
' >/dev/null
nix eval --raw "$ci_config.systemd.services.github-runner-tsurumi.environment.SSL_CERT_FILE" |
  grep -qx '/etc/ssl/certs/ca-certificates.crt'
