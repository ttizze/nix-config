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
    brew upgrade --cask 1password 1password-cli chatgpt claude cmux discord google-chrome karabiner-elements logi-options+ zed
