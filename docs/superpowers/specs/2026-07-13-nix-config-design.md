# Personal Nix Configuration Design

Status: implemented locally; Darwin build verified; Linux evaluated with native CI configured; not activated
Date: 2026-07-13

## Purpose

Provide one reproducible source of truth for:

- the Apple Silicon Mac `tinoMac-mini`;
- the user `tt` on macOS;
- the shared interactive user environment on `aarch64-linux` and `x86_64-linux`;
- new project toolchains without hidden machine-global runtime dependencies.

The machine repository is `nix-config`. Stable agent policy and custom skills live in the separate `agent-config` repository. Runtime state, credentials, caches, histories, and application databases belong in neither repository.

## Principles

1. Declare desired state, not an inventory of everything currently installed.
2. Keep system, user, project, secret, and mutable application state at separate ownership boundaries.
3. Pin dependencies and build before activation.
4. Keep the interactive global baseline small.
5. Put project runtimes and deployment CLIs in each project.
6. Never resolve a secret into Git, a shell startup file, or the Nix store.
7. Do not delete or upgrade unrelated applications as a side effect of normal activation.

## Ownership

### Lix

Lix is the installed Nix implementation and the package selected by nix-darwin. Flakes and the `nix` command are enabled by the installer.

### nix-darwin

nix-darwin owns supported macOS state:

- host name and time zone;
- Nix daemon, garbage collection, and store optimisation;
- firewall, Touch ID for sudo, and automatic macOS updates;
- stable Finder, Dock, keyboard, and cmux defaults;
- the declared Homebrew cask set;
- the embedded Home Manager configuration for `tt`.

### Home Manager

Home Manager owns stable user state:

- the small CLI baseline;
- zsh and Starship;
- Git, SSH includes, direnv, nix-direnv, fzf, zoxide, and tmux;
- stable Karabiner-Elements and Zed configuration files;
- shared Linux user configurations.

Home Manager does not own histories, login sessions, caches, recent files, window geometry, application databases, or agent conversation state.

### Homebrew

Homebrew exists only for native macOS applications that are unsuitable as ordinary Nix packages. The desired casks are:

- 1Password and 1Password CLI;
- ChatGPT and Claude;
- cmux;
- Discord;
- Google Chrome;
- Karabiner-Elements;
- Logitech Options+;
- Zed.

Circleback remains unmanaged because no matching Homebrew cask is available. Apple applications and Xcode remain Apple-managed.

Normal activation uses `homebrew.onActivation.cleanup = "none"`, does not auto-update Homebrew, and does not upgrade casks. `just apps-update` is the explicit upgrade path.

Hermes and its embedded Node, OrbStack, Open Design, PLUG, and Typeless may remain installed on this Mac. They are intentionally absent from desired state, so a new Mac will not install them and normal activation will not remove them.

## Global and project tool boundary

The global baseline includes ordinary interactive tools plus `blueutil`, GnuPG, and `pinentry-mac`. `blueutil` is the single Homebrew formula exception because the Nixpkgs package fails to link on the current macOS/Xcode toolchain; GnuPG and `pinentry-mac` come from Nix. The baseline does not include mise, Node.js, Bun, pnpm, Wrangler, Vercel CLI, Turso CLI, Fastlane, XcodeGen, CMake, Ninja, Python, or Rust.

Project repositories select their own tools through `flake.nix`, `flake.lock`, `.envrc`, and a `justfile`. The machine repository exports templates for:

- minimal Nix projects;
- Bun projects;
- Node.js 24 and pnpm projects;
- Python 3.13 and uv projects;
- iOS projects with Nix-owned Ruby, Bundler, XcodeGen, and Gemfile-owned Fastlane.

Cloudflare, Vercel, and Turso are additive recipes. A project installs only the deployment or database CLI it actually uses.

Python uses a split boundary: Nix owns Python and uv; uv owns project dependencies and `.venv`; uv is forbidden from downloading its own Python interpreter.

## Shell and application behavior

- Use zsh with Starship.
- Do not use Oh My Zsh, Powerlevel10k, mise activation, or global Bun initialization.
- Preserve the approved aliases, navigation helpers, Git behavior, 1Password SSH Agent socket, and SSH includes.
- Link stable Zed settings, including the Codex ACP registry entry and system-aware theme.

Karabiner-Elements preserves:

- Caps Lock as left Control;
- left Command alone as Eisuu and right Command alone as Kana;
- the approved Japanese Muhenkan and Henkan behavior;
- the current Logitech device's button swap;
- a JIS virtual keyboard.

Shift-Command-3 and Shift-Command-4 add Control so static screenshots go to the clipboard. Shift-Command-5 remains unchanged for screen recording and advanced capture controls.

## Secrets

1Password is the source of truth for interactive credentials, SSH keys, signing keys, and personal profile data.

- Tracked `.env.op` files may contain reviewed `op://` references.
- Commands resolve references only for the process that needs them with `op run` or `op inject`.
- Resolved values, private keys, session tokens, and authentication state are forbidden in both repositories.
- `agent-config` profile lookup requests only allowlisted fields and fails on missing or duplicate values.
- Unattended services may add sops-nix later, but only when an actual pre-login secret requirement exists.

## Agent configuration repository

`agent-config` contains only stable, publishable policy:

- Codex rules and keybindings;
- Claude permissions and hooks;
- custom skills and their safe scripts;
- a Home Manager module that links those files into the user home.

Device IDs, Apple team IDs, build IDs, contact values, authentication files, sessions, caches, and project trust state are excluded. Machine integration waits for a stable remote; the Nix repository does not embed an absolute local path.

## Activation and rollback

The normal flow is:

1. `just check`
2. `just build`
3. `just diff`
4. commit the exact source being activated
5. `just apply`
6. open a fresh terminal and reboot before removing any legacy manager or authentication method

`just apply` refuses the wrong host, a dirty worktree, or an unbuilt configuration. `just rollback` activates the previous nix-darwin system generation. Homebrew app state and mutable application data are deliberately outside Nix generation rollback.

## Acceptance criteria

- all supported outputs evaluate and build;
- the Darwin system builds without switching;
- Linux Home Manager activation packages build;
- every project template enters its pinned shell and passes its smoke test;
- no forbidden runtime or deployment CLI appears in the global package set;
- declared casks exactly match the approved desired set;
- normal activation neither removes unmanaged applications nor upgrades casks;
- no secret value, private key, authentication state, or hard-coded device identifier is tracked;
- the user explicitly approves the first activation after reviewing the build and diff.
