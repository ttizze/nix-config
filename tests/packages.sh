#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

circleback="$(nix build .#circleback-cli --no-link --print-out-paths)"

test "$("$circleback/bin/cb" --version)" = '0.2.2'
help="$("$circleback/bin/circleback" --help)"
grep -Fq 'Search and access meetings, emails, calendar events, and more.' <<<"$help"
test ! -e "$circleback/bin/node"
test ! -e "$circleback/bin/npm"

echo 'package checks passed'
