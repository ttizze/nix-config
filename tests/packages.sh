#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

circleback="$(nix build .#circleback-cli --no-link --print-out-paths)"
claude_agent_acp="$(nix build .#claude-agent-acp --no-link --print-out-paths)"
codex_acp="$(nix build .#codex-acp --no-link --print-out-paths)"

test "$("$circleback/bin/cb" --version)" = '1.1.1'
help="$("$circleback/bin/circleback" --help)"
grep -Fq 'Usage: circleback [options] [command]' <<<"$help"
test ! -e "$circleback/bin/node"
test ! -e "$circleback/bin/npm"

test "$("$claude_agent_acp/bin/claude-agent-acp" --version)" = '0.93.0'
test ! -e "$claude_agent_acp/bin/node"
test ! -e "$claude_agent_acp/bin/npm"
test ! -e "$claude_agent_acp/bin/npx"

test "$("$codex_acp/bin/codex-acp" --version)" = '@agentclientprotocol/codex-acp 2.3.0'
test ! -e "$codex_acp/bin/node"
test ! -e "$codex_acp/bin/npm"
test ! -e "$codex_acp/bin/npx"

echo 'package checks passed'
