#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

package_count="$(nix eval --raw .#darwinConfigurations.tinoMac-mini.config.home-manager.users.tt.home.packages --apply 'packages: builtins.toString (builtins.length packages)')"
test "$package_count" -ge 20

nix eval --json .#darwinConfigurations.tinoMac-mini.config.home-manager.users.tt.programs.zsh.enable | jq -e '. == true' >/dev/null
nix eval --json .#darwinConfigurations.tinoMac-mini.config.home-manager.users.tt.programs.git.enable | jq -e '. == true' >/dev/null
nix eval --json .#darwinConfigurations.tinoMac-mini.config.home-manager.users.tt.programs.ssh.includes | jq -e 'index("~/.ssh/1Password/config") and index("~/.ssh/config.local")' >/dev/null
nix eval --raw .#darwinConfigurations.tinoMac-mini.config.home-manager.users.tt.home.sessionVariables.SSH_AUTH_SOCK | grep -Fqx '/Users/tt/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock'
