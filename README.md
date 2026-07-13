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
