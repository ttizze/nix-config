#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export AGMSG_TEST_CURL_LOG="$tmp/curl.log"
export AGMSG_TEST_INSTALLER_LOG="$tmp/installer.log"
export AGMSG_TEST_SETUP_FIXTURE="$repo_root/tests/fixtures/agmsg/setup.sh"
export PATH="$repo_root/tests/fixtures/agmsg:$PATH"

setup_url='https://raw.githubusercontent.com/fujibee/agmsg/main/setup.sh'

scripts/agmsg install
grep -Fxq "$setup_url" "$AGMSG_TEST_CURL_LOG"
grep -Fxq 'args=' "$AGMSG_TEST_INSTALLER_LOG"

: >"$AGMSG_TEST_CURL_LOG"
: >"$AGMSG_TEST_INSTALLER_LOG"
scripts/agmsg update
grep -Fxq "$setup_url" "$AGMSG_TEST_CURL_LOG"
grep -Fxq 'args=--update' "$AGMSG_TEST_INSTALLER_LOG"

: >"$AGMSG_TEST_CURL_LOG"
if scripts/agmsg invalid >/dev/null 2>&1; then
  echo 'invalid agmsg action unexpectedly succeeded' >&2
  exit 1
fi
test ! -s "$AGMSG_TEST_CURL_LOG"

grep -Eq '^agmsg-install:' justfile
grep -Eq '^agmsg-update:' justfile

echo 'agmsg lifecycle checks passed'
