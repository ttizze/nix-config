#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

in_template() {
  local template="$1"
  local command="$2"
  nix develop "path:$repo_root/templates/$template" \
    --command bash -c "cd '$repo_root/templates/$template' && $command"
}

in_template minimal 'just --list >/dev/null'
in_template bun 'bun install --frozen-lockfile && bun test'
in_template node-pnpm 'pnpm install --frozen-lockfile && pnpm test'
in_template python-uv 'uv sync --locked && uv run ruff check . && uv run pytest'
# mktemp must run inside the template dev shell.
# shellcheck disable=SC2016
in_template ios 'bundle config set --local path vendor/bundle && bundle install --jobs 4 --retry 2 && xcodegen --spec project.yml --project "$(mktemp -d)" --quiet && bundle exec fastlane lanes >/dev/null'

echo "project template smoke tests passed"
