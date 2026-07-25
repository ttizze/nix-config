#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

circleback="$(nix build .#circleback-cli --no-link --print-out-paths)"
codex_acp="$(nix build .#codex-acp --no-link --print-out-paths)"

test "$("$circleback/bin/cb" --version)" = '0.2.2'
help="$("$circleback/bin/circleback" --help)"
grep -Fq 'Search and access meetings, emails, calendar events, and more.' <<<"$help"
test ! -e "$circleback/bin/node"
test ! -e "$circleback/bin/npm"

test "$("$codex_acp/bin/codex-acp" --version)" = '@agentclientprotocol/codex-acp 1.1.7'
test ! -e "$codex_acp/bin/node"
test ! -e "$codex_acp/bin/npm"
test ! -e "$codex_acp/bin/npx"

echo 'package checks passed'
