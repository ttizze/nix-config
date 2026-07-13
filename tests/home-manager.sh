#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

config='.#darwinConfigurations.tinoMac-mini.config.home-manager.users.tt'

nix flake metadata --json | jq -e '.locks.nodes | has("hermes-agent") | not' >/dev/null
nix flake metadata --json | jq -e '.locks.nodes | has("agent-config")' >/dev/null

nix eval --json "$config.programs.zsh.enable" | jq -e '. == true' >/dev/null
nix eval --json "$config.programs.starship.enable" | jq -e '. == true' >/dev/null
nix eval --json "$config.programs.zsh.oh-my-zsh.enable" | jq -e '. == false' >/dev/null
nix eval --json "$config.programs.direnv.nix-direnv.enable" | jq -e '. == true' >/dev/null
nix eval --json "$config.programs.git.enable" | jq -e '. == true' >/dev/null
nix eval --json "$config.programs.git.settings.alias.clean-gone" | jq -e 'type == "string"' >/dev/null
nix eval --json "$config.programs.ssh.includes" | jq -e 'index("~/.ssh/1Password/config") and index("~/.ssh/config.local")' >/dev/null
nix eval --raw "$config.home.sessionVariables.SSH_AUTH_SOCK" | grep -Fqx '/Users/tt/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock'

nix eval --json "$config.home.packages" --apply 'packages: map (package: package.name) packages' |
  jq -e '
    any(.[]; startswith("claude-code-")) and
    any(.[]; startswith("codex-")) and
    any(.[]; startswith("dcg-")) and
    any(.[]; startswith("gnupg-")) and
    any(.[]; startswith("pinentry-mac-")) and
    all(.[];
      test("^(blueutil|bun|nodejs|pnpm|turso-cli|wrangler|vercel|mise|hermes-agent|tree|wget|xcodegen|fastlane|cmake|ninja)-")
      | not
    )
  ' >/dev/null

nix eval --json "$config.home.file" --apply 'files: builtins.attrNames files' |
  jq -e '
    any(.[]; endswith("/.config/karabiner/karabiner.json")) and
    any(.[]; endswith("/.config/zed/settings.json")) and
    any(.[]; endswith(".codex/keybindings.json")) and
    any(.[]; endswith(".codex/rules/default.rules")) and
    any(.[]; endswith(".codex/skills/use-1password-profile")) and
    any(.[]; endswith(".claude/settings.json")) and
    all(.[]; endswith("/.p10k.zsh") | not) and
    all(.[]; endswith("/.wezterm.lua") | not)
  ' >/dev/null

jq -e '
  .profiles[0].simple_modifications[0].from.key_code == "caps_lock" and
  .profiles[0].simple_modifications[0].to[0].key_code == "left_control" and
  ((.profiles[0].complex_modifications.rules | map(.manipulators | length) | add) == 6)
' config/karabiner.json >/dev/null
jq -e '.profiles[0].devices[0].identifiers == {"is_pointing_device": true, "product_id": 50495, "vendor_id": 1133}' config/karabiner.json >/dev/null
jq -e '
  [.profiles[0].complex_modifications.rules[].manipulators[]
    | select(.from.key_code == "3" or .from.key_code == "4")
    | .to[0].modifiers
    | index("left_control")]
  | length == 2 and all(.[]; . != null)
' config/karabiner.json >/dev/null
jq -e '.agent_servers."codex-acp".type == "registry" and .theme.mode == "system"' config/zed-settings.json >/dev/null

nix eval --raw '.#homeConfigurations."tt@linux-aarch64".activationPackage.drvPath' >/dev/null
nix eval --raw '.#homeConfigurations."tt@linux-x86_64".activationPackage.drvPath' >/dev/null
