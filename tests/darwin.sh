#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

config='.#darwinConfigurations.tinoMac-mini.config'

nix eval --raw "$config.nix.package.pname" | grep -qx 'lix'
nix eval --json "$config.nix.gc.automatic" | jq -e '. == true' >/dev/null
nix eval --raw "$config.time.timeZone" | grep -qx 'Asia/Tokyo'
nix eval --raw "$config.networking.computerName" | grep -qx 'tのMac mini'
nix eval --raw "$config.networking.localHostName" | grep -qx 'tinoMac-mini'

nix eval --json "$config.security.pam.services.sudo_local.touchIdAuth" | jq -e '. == true' >/dev/null
nix eval --json "$config.networking.applicationFirewall" |
  jq -e '
    .enable == null and
    .blockAllIncoming == null and
    .allowSigned == null and
    .allowSignedApp == null and
    .enableStealthMode == null
  ' >/dev/null
nix eval --json "$config.system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates" |
  jq -e '. == null' >/dev/null

nix eval --raw "$config.system.defaults.finder.FXPreferredViewStyle" | grep -qx 'Nlsv'
nix eval --json "$config.system.defaults.finder.AppleShowAllExtensions" | jq -e '. == true' >/dev/null
nix eval --json "$config.system.defaults.finder.ShowPathbar" | jq -e '. == true' >/dev/null
nix eval --json "$config.system.defaults.finder.ShowStatusBar" | jq -e '. == true' >/dev/null
nix eval --json "$config.system.defaults.dock.autohide" | jq -e '. == null' >/dev/null
nix eval --json "$config.system.defaults.dock.autohide-delay" | jq -e '. == null' >/dev/null
nix eval --json "$config.system.defaults.dock.show-recents" | jq -e '. == false' >/dev/null
nix eval --json "$config.system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled" | jq -e '. == false' >/dev/null
nix eval --json "$config.system.defaults.NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled" | jq -e '. == false' >/dev/null

nix eval --json "$config.homebrew.casks" |
  jq -e 'map(.name) == [
    "1password",
    "1password-cli",
    "chatgpt",
    "claude",
    "cmux",
    "discord",
    "google-chrome",
    "karabiner-elements",
    "logi-options+",
    "zed"
  ]' >/dev/null
nix eval --json "$config.homebrew.brews" | jq -e 'map(.name) == ["blueutil"]' >/dev/null
nix eval --raw "$config.homebrew.onActivation.cleanup" | grep -qx 'none'
nix eval --json "$config.homebrew.onActivation.autoUpdate" | jq -e '. == false' >/dev/null
nix eval --json "$config.homebrew.onActivation.upgrade" | jq -e '. == false' >/dev/null
nix eval --json "$config.nix-homebrew.enable" | jq -e '. == true' >/dev/null

nix eval --json "$config.system.defaults.CustomUserPreferences.\"com.cmuxterm.app\"" |
  jq -e '
    .confirmQuit == "never" and
    .appearanceMode == "system" and
    ."rightSidebar.mode" == "files"
  ' >/dev/null
