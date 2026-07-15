#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

test -f justfile
test -f README.md
test -f .github/workflows/check.yml
test -x tests/secrets.sh
test -x tests/templates.sh
test -x tests/agmsg.sh
test -x scripts/setup-agent-config-ssh
test -x scripts/agmsg
test -x tests/fixtures/agmsg/curl
test -x tests/fixtures/agmsg/setup.sh
test -f pkgs/circleback-cli/default.nix
test -f pkgs/circleback-cli/package.json
test -f pkgs/circleback-cli/package-lock.json
grep -Fq 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' scripts/setup-agent-config-ssh
if grep -Fq 'ssh-keyscan' scripts/setup-agent-config-ssh; then
  echo 'setup-agent-config-ssh must use the pinned GitHub host key' >&2
  exit 1
fi
grep -Fq 'bash tests/secrets.sh' justfile
grep -Fq 'bash tests/agmsg.sh' justfile
grep -Fq 'bash tests/packages.sh' justfile
grep -Fq 'bash tests/templates.sh' justfile
grep -Fq 'ubuntu-24.04-arm' .github/workflows/check.yml
grep -Fq 'tt@linux-aarch64' .github/workflows/check.yml
grep -Fq 'tt@linux-x86_64' .github/workflows/check.yml
grep -Fq 'git+ssh://git@github.com/ttizze/agent-config.git?ref=main' flake.nix
# shellcheck disable=SC2016 # This is a literal GitHub Actions expression.
test "$(grep -Fc 'AGENT_CONFIG_SSH_KEY: ${{ secrets.AGENT_CONFIG_SSH_KEY }}' .github/workflows/check.yml)" -eq 2
test "$(grep -Fc "github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository" .github/workflows/check.yml)" -eq 2
jq -e '
  .nodes["agent-config"].locked.type == "git" and
  .nodes["agent-config"].locked.url == "ssh://git@github.com/ttizze/agent-config.git" and
  .nodes["agent-config"].original.type == "git" and
  .nodes["agent-config"].original.ref == "main"
' flake.lock >/dev/null

for template in minimal bun node-pnpm python-uv ios; do
  test -f "templates/$template/flake.nix"
  test -f "templates/$template/.envrc"
  test -f "templates/$template/.env.op"
  test -f "templates/$template/justfile"
  test -f "templates/$template/AGENTS.md"
  test -f "templates/$template/CLAUDE.md"
  grep -Fxq '@AGENTS.md' "templates/$template/CLAUDE.md"
  grep -Fq 'This repository is Nix-managed.' "templates/$template/AGENTS.md"
  grep -Fq 'Do not run project toolchain commands in a bare shell.' "templates/$template/AGENTS.md"
  # shellcheck disable=SC2016
  grep -Fq 'Do not assume `.envrc` is loaded in agent or non-interactive shells.' "templates/$template/AGENTS.md"
  # shellcheck disable=SC2016
  grep -Fq 'When `IN_NIX_SHELL` is unset, run project commands with `nix develop --command <command>`.' "templates/$template/AGENTS.md"
done

test -f templates/bun/package.json
test -f templates/bun/bun.lock
test -f templates/bun/src/index.ts
test -f templates/bun/src/index.test.ts
test -f templates/node-pnpm/package.json
test -f templates/node-pnpm/pnpm-lock.yaml
test -f templates/node-pnpm/src/index.js
test -f templates/node-pnpm/src/index.test.js
test -f templates/python-uv/pyproject.toml
test -f templates/python-uv/uv.lock
test -f templates/python-uv/src/python_project/__init__.py
test -f templates/python-uv/tests/test_package.py
test -f templates/ios/Gemfile
test -f templates/ios/Gemfile.lock
test -f templates/ios/.xcode-version
test -f templates/ios/project.yml
test -f templates/ios/fastlane/Fastfile
test -f templates/ios/Sources/App.swift
test -f templates/ios/Tests/AppTests.swift

for recipe in cloudflare vercel turso; do
  test -f "recipes/$recipe.md"
done

nix eval --json .#templates --apply builtins.attrNames |
  jq -e '. == ["bun", "default", "ios", "minimal", "node-pnpm", "python-uv"]' >/dev/null

for recipe in check build diff apply update rollback agmsg-install agmsg-update; do
  grep -Eq "^${recipe}([[:space:]].*)?:" justfile
done

test ! -e files/p10k.zsh
test ! -e files/wezterm.lua
