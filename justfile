set default-list := true
set shell := ["bash", "-euo", "pipefail", "-c"]

host := "tinoMac-mini"

# Run all repository and project-template checks.
check: check-core check-templates

# Check the managed system and repository without executing project templates.
check-core:
    shellcheck scripts/* tests/*.sh tests/fixtures/agmsg/*
    bash tests/agmsg.sh
    bash tests/secrets.sh
    bash tests/eval.sh
    bash tests/home-manager.sh
    bash tests/packages.sh
    bash tests/darwin.sh
    bash tests/structure.sh
    nix flake check --show-trace

# Smoke-test every project template.
check-templates:
    bash tests/templates.sh

# Build the Mac configuration without activating it.
build:
    nix build ".#darwinConfigurations.{{host}}.system"

# Compare the current system generation with the new build.
diff: build
    #!/usr/bin/env bash
    if [[ -e /run/current-system ]]; then
      nvd diff /run/current-system ./result
    else
      echo "No nix-darwin generation is active yet; this is the first activation."
    fi

# Apply only a clean, checked, already-built configuration.
apply: check-core build
    scripts/apply "{{host}}"

# Update one input, or all inputs when no name is supplied.
update input="":
    scripts/update "{{input}}"

# Roll back to the previous nix-darwin generation.
rollback:
    scripts/rollback

# Install agmsg from its official main branch.
agmsg-install:
    scripts/agmsg install

# Update an existing agmsg installation from its official main branch.
agmsg-update:
    scripts/agmsg update

# Explicitly update declared Homebrew casks; normal apply never upgrades them.
apps-update:
    brew update
    brew upgrade --cask 1password 1password-cli nikitabobko/tap/aerospace chatgpt claude cmux discord google-chrome karabiner-elements logi-options+ zed

# Build the shared CI host remotely without activation.
build-ci:
    nix run --inputs-from . nixpkgs-server#nixos-rebuild -- build --flake .#ci-1 --build-host root@46.62.235.116 --target-host root@46.62.235.116

# Apply committed infrastructure only while every runner is idle.
apply-ci: build-ci
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Refusing to apply from a dirty Git worktree." >&2
      exit 1
    fi
    for repo in cinema-maker agent-config nix-config; do
      busy="$(gh api "repos/ttizze/$repo/actions/runners" --jq 'any(.runners[]; .busy)')"
      if [[ "$busy" != false ]]; then
        echo "Runner for $repo is busy; wait for the job to finish." >&2
        exit 1
      fi
    done
    nix run --inputs-from . nixpkgs-server#nixos-rebuild -- switch --flake .#ci-1 --build-host root@46.62.235.116 --target-host root@46.62.235.116
