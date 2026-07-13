#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

credential_pattern='AKIA[0-9A-Z]{16}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}'
private_key_pattern='BEGIN (OPENSSH|RSA|EC|DSA|PGP|PRIVATE) PRIVATE KEY'

matches="$(
  git grep --cached -I -nE "$credential_pattern|$private_key_pattern" \
    -- . ':(exclude)tests/secrets.sh' || true
)"
if [[ -n "$matches" ]]; then
  echo "Possible resolved credential or private key in tracked files:" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

while IFS= read -r env_file; do
  awk '
    /^[[:space:]]*($|#)/ { next }
    !/^[A-Za-z_][A-Za-z0-9_]*=op:\/\// {
      print FILENAME ":" FNR ": .env.op values must be op:// references" > "/dev/stderr"
      failed = 1
    }
    END { exit failed }
  ' "$env_file"
done < <(git ls-files 'templates/*/.env.op')

echo "tracked secret scan passed"
