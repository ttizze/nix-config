# nix-config

Reproducible configuration for `tt` on the Apple Silicon Mac `tinoMac-mini`, plus the shared interactive CLI environment used on Linux hosts.

## Ownership

- Lix provides the Nix implementation.
- nix-darwin owns macOS system settings and declared native applications.
- Home Manager owns the stable user CLI and configuration files.
- Homebrew is used for declared macOS applications and the reviewed `blueutil` formula exception.
- Project runtimes and deployment tools belong to each project.
- Secrets remain in 1Password and are injected per process with `op run`.
- Stable Codex and Claude instructions and custom skills come from the pinned `ttizze/agent-config` flake.

Existing unmanaged applications are not removed automatically. Homebrew cleanup is intentionally `none`, and normal activation never upgrades casks.

## Commands

Enter the repository shell automatically with direnv, or explicitly:

```sh
nix develop
```

Then use the shared command interface:

```sh
just check
just build
just diff
just apply
just update nixpkgs
just rollback
```

`just apply` refuses the wrong host and a dirty Git worktree. It builds before requesting `sudo`. `just apps-update` is the only command that explicitly upgrades declared Homebrew casks.

## First activation

1. Install Lix with the multi-user installer.
2. Run `nix develop -c just check`.
3. Run `nix develop -c just build`.
4. Review `nix develop -c just diff`.
5. Commit the exact source being activated.
6. Run `nix develop -c just apply`.
7. Open a new shell and reboot before removing any legacy tool.

## Project environments

Initialize a project with one runtime template:

```sh
nix flake init -t github:ttizze/nix-config#bun
nix flake init -t github:ttizze/nix-config#node-pnpm
nix flake init -t github:ttizze/nix-config#python-uv
nix flake init -t github:ttizze/nix-config#ios
```

Cloudflare, Vercel, and Turso are additive recipes under `recipes/`; they are not separate runtime managers.

## Recovery

Run `just rollback` to select and activate the previous nix-darwin generation. If the interactive shell is broken, start `/bin/zsh -f`, source `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`, enter this repository, and run `nix develop -c just rollback`.

Homebrew application changes, authentication sessions, application databases, histories, and caches are outside Nix generation rollback and are never deleted by normal activation.

## Shared Hetzner CI

`hosts/ci-1/default.nix` owns the NixOS configuration for the existing
Hetzner CX33 in Helsinki (`46.62.235.116`). Product repositories own their
workflows, not this shared host. The `nixpkgs-server` and `disko` inputs pin its
OS and disk configuration separately from the Mac environment.

The host runs repository-scoped runners for `cinema-maker`, `agent-config`,
`nix-config`, and `remote-agent`, with separate users and working directories.
Only the `cinema-maker` runner has Docker access; its workflow selects
`[self-hosted, linux, x64, tsurumi-ci]`. The other repositories select
`[self-hosted, linux, x64, nix-ci]`. `remote-agent` runs its native Linux build,
Core and isolated Host tests, and Rust toolchain lookup here.
ARM Linux builds run through QEMU; native macOS and Windows CI stay on GitHub-hosted runners.
Nix builds are limited to one at a time with two build cores.

`pkgs/github-runner` supplies the official Node 20.20.2 binary required by
runner 2.337.0's internal `hashFiles()` helper. Nixpkgs has removed Node 20,
while the runner's internal runtime selection still requires it. This explicit
exception is confined to the runner package; JavaScript actions continue on
Node 24 and project runtimes remain project-owned. The package build exercises
the installed hash helper against known file contents. Remove the extra runtime
when the upstream runner moves its internal helpers to Node 24.

Use `nix develop --command hcloud server list` to inspect the Hetzner project.
Keep its CLI credentials outside the repository.

Build with `just build-ci`, then apply with `just apply-ci` when all
runners are idle. These commands update the existing server without formatting
its disks. Verify the runner services and their GitHub online status afterward.

For initial registration, issue a short-lived registration token locally for
each repository using `gh api --method POST repos/ttizze/REPOSITORY/actions/runners/registration-token`.
Transfer only that token to the corresponding root-owned mode-0600 file:

- `cinema-maker`: `/var/lib/tsurumi-ci-registration-token`
- `agent-config`: `/var/lib/agent-config-ci-registration-token`
- `nix-config`: `/var/lib/nix-config-ci-registration-token`
- `remote-agent`: `/var/lib/remote-agent-ci-registration-token`

Do not store long-lived GitHub access tokens on the server. Registration state
persists across ordinary package updates; new tokens are needed if registration
settings change. Keep the Nix-managed runner package current; it does not self-update.

The experimental `codex-model-router` package and LaunchAgent have been removed.
