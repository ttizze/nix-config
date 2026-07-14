# agmsg Installer Design

## Goal

Add simple, explicit commands for installing and updating agmsg from its
official `main` branch without adding global Node.js or npm.

## Decisions

- `just agmsg-install` performs the first installation.
- `just agmsg-update` updates an existing installation.
- Both commands download the official
  `https://raw.githubusercontent.com/fujibee/agmsg/main/setup.sh` entrypoint.
- The commands intentionally follow upstream `main`; no agmsg version or Nix
  flake input is pinned.
- Updates are manual. Normal Nix builds and `darwin-rebuild` activation never
  contact upstream or update agmsg.
- agmsg owns its mutable runtime under `~/.agents/skills/agmsg`, including its
  SQLite database, team configuration, and generated agent integration files.
  Those files do not enter Git or the Nix store.
- `agent-config` does not copy or deploy agmsg because agmsg must write inside
  its own skill tree.

## Components

`scripts/agmsg` is the single lifecycle wrapper. It accepts exactly `install`
or `update`, downloads the current official setup script into a temporary file,
and invokes it with no argument for installation or `--update` for updating.
It uses the already managed `curl` command and does not invoke Node.js, npm, or
npx.

The root `justfile` exposes the wrapper as `agmsg-install` and `agmsg-update`.
Neither recipe is part of `check`, `build`, or `apply` because those workflows
must remain deterministic and offline with respect to agmsg.

## Error Handling

- The wrapper uses `set -euo pipefail` and `curl -fsSL`, so download and
  installer failures propagate as non-zero exits.
- Unknown wrapper actions fail before making a network request.
- The temporary setup script is removed on every exit.
- Following an unpinned remote `main` means installation executes the current
  upstream code. This is an explicit trade-off accepted in exchange for easy
  access to agmsg updates.

## Testing

A shell test replaces `curl` with a local fixture so it can verify without
network access that:

- installation invokes the downloaded setup script with no arguments;
- updating passes exactly `--update`;
- both operations request the official `main` URL;
- an unknown action fails without invoking the downloader;
- the two Just recipes and repository checks include the lifecycle wrapper.

The existing secret scan, ShellCheck, Nix evaluation, project-template tests,
and flake checks remain unchanged and must all pass before publication.

## Publication and Use

Implement on an isolated worktree, merge locally to `main`, push, and verify
GitHub Actions. Then run `just agmsg-install` once on this Mac and confirm the
agmsg Skill, Claude command, SQLite database, and installed version exist.
Future updates use `just agmsg-update` followed by the same verification.
