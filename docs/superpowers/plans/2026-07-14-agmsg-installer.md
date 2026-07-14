# agmsg Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit `just agmsg-install` and `just agmsg-update` commands that execute the official agmsg `main` installer without installing Node.js or npm.

**Architecture:** A single shell wrapper validates an `install` or `update` action, downloads the official setup entrypoint to a temporary file, and invokes it. Just recipes expose the two operations; a fake downloader tests the complete wrapper behavior without network access.

**Tech Stack:** Bash, Just, curl, existing shell test harness

## Global Constraints

- Follow `https://raw.githubusercontent.com/fujibee/agmsg/main/setup.sh`; do not pin an agmsg version.
- Do not add Node.js, npm, npx, a Nix package, or a flake input.
- Do not run agmsg installation or updates from `check`, `build`, `apply`, or Home Manager activation.
- Keep `~/.agents/skills/agmsg` and all generated runtime state outside Git and the Nix store.

---

### Task 1: Add tested agmsg lifecycle commands

**Files:**
- Create: `scripts/agmsg`
- Create: `tests/agmsg.sh`
- Create: `tests/fixtures/agmsg/curl`
- Create: `tests/fixtures/agmsg/setup.sh`
- Modify: `justfile`
- Modify: `tests/structure.sh`

**Interfaces:**
- Consumes: the managed `curl` and Bash commands plus the official agmsg `main/setup.sh` URL.
- Produces: `scripts/agmsg install`, `scripts/agmsg update`, `just agmsg-install`, and `just agmsg-update`.

- [ ] **Step 1: Write the failing behavior test and fixtures**

Create `tests/fixtures/agmsg/setup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

printf 'args=%s\n' "$*" >>"$AGMSG_TEST_INSTALLER_LOG"
```

Create `tests/fixtures/agmsg/curl`:

```bash
#!/usr/bin/env bash
set -euo pipefail

test "$1" = '-fsSL'
url="$2"
test "$3" = '-o'
output="$4"

printf '%s\n' "$url" >>"$AGMSG_TEST_CURL_LOG"
cp "$AGMSG_TEST_SETUP_FIXTURE" "$output"
```

Create `tests/agmsg.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
bash tests/agmsg.sh
```

Expected: FAIL because `scripts/agmsg` and both Just recipes do not exist.

- [ ] **Step 3: Implement the minimal lifecycle wrapper**

Create `scripts/agmsg`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: scripts/agmsg <install|update>' >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

case "$1" in
  install | update) action="$1" ;;
  *)
    usage
    exit 2
    ;;
esac

setup="$(mktemp "${TMPDIR:-/tmp}/agmsg-setup.XXXXXX")"
trap 'rm -f "$setup"' EXIT

curl -fsSL 'https://raw.githubusercontent.com/fujibee/agmsg/main/setup.sh' -o "$setup"

if [[ "$action" = update ]]; then
  bash "$setup" --update
else
  bash "$setup"
fi
```

Make the script and fixtures executable. Add these recipes to `justfile`:

```just
# Install the latest agmsg release from its official main branch.
agmsg-install:
    scripts/agmsg install

# Update an existing agmsg installation from its official main branch.
agmsg-update:
    scripts/agmsg update
```

Add `bash tests/agmsg.sh` to the `check` recipe. Extend `tests/structure.sh` with:

```bash
test -x scripts/agmsg
test -x tests/agmsg.sh
test -x tests/fixtures/agmsg/curl
test -x tests/fixtures/agmsg/setup.sh
grep -Fq 'bash tests/agmsg.sh' justfile

for recipe in check build diff apply update rollback agmsg-install agmsg-update; do
  grep -Eq "^${recipe}([[:space:]].*)?:" justfile
done
```

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```bash
bash tests/agmsg.sh
shellcheck scripts/agmsg tests/agmsg.sh tests/fixtures/agmsg/curl tests/fixtures/agmsg/setup.sh
bash tests/structure.sh
```

Expected: all commands exit 0 and the lifecycle test prints `agmsg lifecycle checks passed`.

- [ ] **Step 5: Run complete verification**

Run:

```bash
nix fmt -- --ci
nix develop --command just check
nix develop --command just build
```

Expected: formatter reports zero changed files; all repository checks and the Darwin system build exit 0.

- [ ] **Step 6: Commit implementation**

```bash
git add justfile scripts/agmsg tests/agmsg.sh tests/fixtures/agmsg tests/structure.sh
git commit -m "feat: add agmsg lifecycle commands"
```

- [ ] **Step 7: Merge, publish, install, and verify**

Fast-forward local `main`, push it, and wait for GitHub Actions. Then run:

```bash
just agmsg-install
```

Verify:

```bash
test -f "$HOME/.agents/skills/agmsg/.agmsg"
test -f "$HOME/.agents/skills/agmsg/SKILL.md"
test -f "$HOME/.agents/skills/agmsg/db/messages.db"
test -f "$HOME/.claude/commands/agmsg.md"
test -z "$(command -v node || true)"
test -z "$(command -v npm || true)"
```

Expected: all paths exist, Node.js and npm remain absent globally, and the installed `VERSION` reports the current upstream version.
