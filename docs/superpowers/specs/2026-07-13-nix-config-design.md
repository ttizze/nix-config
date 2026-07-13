# Personal Nix Configuration Design

Status: approved architecture, pending written-spec review
Date: 2026-07-13

## 1. Purpose

Create a clean, reproducible personal environment for:

- the Apple Silicon Mac `tinoMac-mini`;
- interactive CLI use on Ubuntu hosts, on both `x86_64-linux` and `aarch64-linux`;
- the user `tt`;
- rebuilding a new machine without depending on undocumented local state.

The new source of truth will be a public repository named `ttizze/nix-config`. The existing `ttizze/dotfiles` repository is only a migration reference and behavioral baseline. Its history and structure will not be imported into the new repository. After migration is verified, the old repository will be archived.

## 2. First principles

1. **Declare desired state, not runtime state.** Stable configuration belongs in Git. Caches, histories, authentication sessions, generated application state, and machine-local databases do not.
2. **Separate privilege boundaries.** macOS system state and user-home state have different owners and failure modes.
3. **Keep shared configuration genuinely portable.** Common modules must not contain Darwin-only paths or Linux-only service assumptions.
4. **Keep secrets out of Git and the Nix store.** The repository may describe how secrets are accessed, but must not contain their values.
5. **Put project dependencies with the project.** Project-specific Node, Bun, Rust, database, and toolchain versions must not be hidden in the machine configuration.
6. **Pin every dependency and update deliberately.** Reproducibility comes from `flake.lock`, review, checks, and rollback.
7. **Prefer the smallest stable abstraction.** Use plain flakes and Nix modules. Do not add `flake-parts`, a private framework, or duplicated package sets without a demonstrated need.
8. **Build before activation and preserve rollback.** No destructive cleanup occurs until the replacement has passed behavioral verification.

## 3. Chosen stack

### 3.1 Lix

Use Lix as the Nix implementation on macOS and Ubuntu. Lix is compatible with Nix expressions, Nixpkgs, Home Manager, and nix-darwin. Its installer supports macOS and Linux, survives macOS upgrades, and provides an uninstaller.

The installer and runtime implementation are separate decisions. This design intentionally uses Lix for both so Mac and Linux have one operational model.

### 3.2 nix-darwin

nix-darwin owns macOS system-level state:

- supported macOS defaults;
- launchd services;
- system-level Nix and garbage-collection policy;
- shell enablement;
- the Homebrew installation and declared native applications;
- the embedded Home Manager configuration for `tt`.

System packages remain minimal. Tools used only by `tt` belong in Home Manager, not `environment.systemPackages`.

### 3.3 Home Manager

Home Manager owns reproducible user state:

- CLI packages;
- zsh, Git, tmux, fzf, zoxide, direnv, and related program settings;
- portable environment variables and aliases;
- stable configuration files under the home directory;
- OS-specific user configuration selected through Darwin and Linux modules.

On macOS, Home Manager runs as a nix-darwin module so one system activation applies both system and user state. On Ubuntu, Home Manager runs stand-alone and does not attempt to manage the Ubuntu operating system.

### 3.4 Homebrew boundary

Homebrew is not a second source of truth.

- `nix-homebrew` installs and pins Homebrew itself.
- nix-darwin's `homebrew.*` options declare required casks and any unavoidable formula exceptions.
- CLI formulae move to Nix wherever a maintained Nixpkgs package exists.
- Homebrew is retained only for macOS-native applications or packages whose Nix version is unsuitable.
- After migration verification, strict cleanup is enabled so undeclared Homebrew packages are removed on activation.

The initial cask set is `1password`, `1password-cli`, and `orbstack`. A new cask requires an explicit review showing why the application should not come from Nixpkgs or the Mac App Store.

## 4. Repository design

```text
nix-config/
├── flake.nix
├── flake.lock
├── README.md
├── hosts/
│   └── tinoMac-mini/
│       └── default.nix
├── home/
│   └── tt/
│       ├── common.nix
│       ├── darwin.nix
│       └── linux.nix
├── modules/
│   ├── darwin/
│   │   ├── system.nix
│   │   ├── defaults.nix
│   │   └── homebrew.nix
│   └── home/
│       ├── shell.nix
│       ├── git.nix
│       ├── cli.nix
│       ├── terminal.nix
│       └── ssh.nix
├── files/
│   ├── p10k.zsh
│   └── wezterm.lua
├── bin/
│   ├── apply
│   ├── build
│   └── update
└── tests/
```

The layout may omit an empty directory. New modules are created only when they have a distinct responsibility.

The flake exposes:

- `darwinConfigurations.tinoMac-mini` for `aarch64-darwin`;
- Home Manager configurations for `tt` on `x86_64-linux` and `aarch64-linux`;
- checks that evaluate or build all supported outputs.

The repository uses one pinned `nixpkgs-unstable` input. Home Manager and nix-darwin follow that same Nixpkgs input. A second stable package set is not added unless a concrete compatibility problem requires it.

## 5. Configuration ownership

### 5.1 Managed declaratively

- package selection;
- aliases and shell functions;
- zsh plugins and Powerlevel10k;
- Git configuration that is safe to publish;
- tmux, fzf, zoxide, direnv, eza, bat, fd, ripgrep, gh, ghq, jq, yq, and similar CLI configuration;
- WezTerm's stable configuration;
- safe SSH client defaults and inclusion of 1Password-managed configuration;
- supported macOS defaults and declared native applications.

Use native Home Manager options when they express the desired behavior clearly. Keep literal files under `files/` only when a native module would lose behavior or make the configuration harder to understand.

### 5.2 Not managed declaratively

- shell history;
- browser state;
- 1Password vault data;
- GitHub and application login sessions;
- `.claude.json` or similar files when they mix settings with runtime or authentication state;
- Codex, Claude, or plugin caches and generated installation state;
- application databases, logs, and caches;
- private SSH host metadata unless intentionally placed in 1Password.

If an application file contains both stable settings and mutable state, manage only a supported stable fragment or generated template. Do not take ownership of the entire mutable file.

## 6. Development environments

The machine configuration provides a small interactive baseline. Project-specific toolchains live in each project repository:

- `flake.nix` or an equivalent Nix development-shell definition;
- `.envrc` with `use flake`;
- a project-local lock file;
- project checks that verify the environment.

mise is removed after the required projects have an explicit replacement. Node.js 24 LTS and Bun remain in the Home Manager baseline for ad hoc commands, but no project may rely on those implicit versions.

## 7. Secrets design

### 7.1 Interactive and human-owned secrets

1Password is the system of record for:

- SSH private keys;
- Git signing keys;
- API tokens and credentials used interactively;
- passwords and recovery codes.

Rules:

- Do not keep a plaintext `~/.ssh/id_ed25519` after key rotation is verified.
- Generate a new SSH key inside 1Password, update authorized public keys, verify access, and only then retire the old local key.
- Use the 1Password SSH Agent for SSH authentication and Git signing.
- Use `op run`, `op inject`, or a supported 1Password shell plugin to inject API credentials into one process.
- Do not export long-lived secrets from `.zshrc`, Home Manager, or nix-darwin.
- Do not put concrete vault names, item names, or secret-reference URIs in the public machine repository unless there is a reviewed reason.

### 7.2 Unattended services

1Password is not sufficient for a service that must start before an interactive login or vault unlock. When such a service appears, add `sops-nix` for that service only:

- commit only SOPS-encrypted material;
- use a host-specific age recipient;
- store the host age private key locally with strict permissions;
- back up that age private key in 1Password;
- decrypt into the platform runtime-secret directory, not the Nix store;
- grant each service access only to its required secret.

Do not add sops-nix before an unattended secret is actually required.

### 7.3 CI secrets

CI secrets remain in the CI provider's secret store or use a least-privilege 1Password service account. They are not reused from an interactive personal session.

## 8. Activation and update flow

### 8.1 New Mac

1. Install the Lix multi-user runtime through the Lix installer.
2. Clone `ttizze/nix-config`.
3. Build the `tinoMac-mini` configuration without activation.
4. Activate nix-darwin, which also activates Home Manager.
5. Open a fresh terminal and run smoke tests.
6. Reboot and repeat the smoke tests before removing legacy managers.

### 8.2 New Ubuntu host

1. Install the Lix multi-user runtime. Supported Ubuntu hosts must use systemd and provide sudo access for bootstrap; rootless hosts are outside the initial scope.
2. Clone `ttizze/nix-config`.
3. Build the matching Linux Home Manager output.
4. Activate Home Manager.
5. Start a fresh shell and run smoke tests.

The implementation will provide `bin/build`, `bin/apply`, and `bin/update` wrappers. The wrappers must print the exact target and refuse unknown hosts instead of guessing.

### 8.3 Updates

1. Update selected flake inputs explicitly.
2. Review the lock-file diff.
3. Run all repository checks.
4. Build the local host without activation.
5. Activate only after checks pass.
6. Keep previous generations until the new configuration has survived normal use and a reboot.

No unattended job automatically changes `flake.lock` or activates a new generation.

## 9. Failure handling and rollback

- A failed evaluation or build makes no system changes.
- Activation scripts must be idempotent and fail with actionable errors.
- Existing home files are inventoried and backed up before Home Manager takes ownership.
- Home Manager file collisions stop activation; they are not silently overwritten.
- Homebrew cleanup remains non-destructive during migration.
- nix-darwin and Home Manager generations provide rollback after activation.
- The old dotfiles checkout, Homebrew formulae, mise installation, and local SSH key remain intact until their replacements pass verification.
- If a reboot exposes a shell or PATH regression, roll back the generation before changing additional variables.

The migration must never delete an authentication method until a replacement has been exercised against every required Git host and server.

## 10. Verification

### 10.1 Static and build checks

- format and parse all Nix files;
- run `nix flake check`;
- build the Darwin configuration without switching;
- build both supported Linux Home Manager activation packages;
- detect unresolved or unsupported packages on each platform;
- scan tracked files and built configuration sources for accidental secret values and forbidden private-key material.

### 10.2 Behavioral smoke tests

- a login zsh and interactive zsh start without warnings;
- expected aliases and functions exist;
- `git`, `gh`, `ghq`, `fzf`, `zoxide`, `direnv`, `tmux`, `bun`, and Node.js 24 LTS resolve from the intended package source;
- GitHub authentication still works;
- Git commit signing works through 1Password;
- SSH works through the 1Password Agent;
- WezTerm starts with the expected appearance and key bindings;
- OrbStack and declared native applications start;
- the Mac passes the same checks after reboot;
- a previous system and Home Manager generation can be selected successfully.

### 10.3 Cross-platform CI

GitHub Actions evaluates and builds the supported outputs on macOS and Ubuntu runners. CI must not require personal secrets. Platform outputs may be evaluated separately when a hosted runner cannot build the target architecture directly.

## 11. Migration sequence

1. Create the new repository with clean history.
2. Capture current behavior and package inventory without importing legacy structure.
3. Implement the flake and module skeleton.
4. Port common CLI packages and shell behavior to Home Manager.
5. Add Darwin system configuration and the strict Homebrew boundary.
6. Build every output without activation.
7. Install Lix and activate the Mac configuration.
8. Run terminal, application, authentication, and reboot verification.
9. Replace project runtimes with project-local Nix environments.
10. Generate and deploy the new 1Password-managed SSH key, then retire the old key after all access paths pass.
11. Remove migrated Homebrew formulae, mise, and chezmoi.
12. Confirm a clean rebuild and rollback.
13. Archive `ttizze/dotfiles`.

Steps that remove legacy state are separate commits and occur only after their exit criteria pass.

## 12. Acceptance criteria

The design is complete when all of the following are true:

- a clean Apple Silicon Mac can reach the declared state from the repository and documented bootstrap steps;
- Ubuntu on both supported architectures can apply the shared user environment;
- the current user-visible shell, terminal, Git, and navigation workflows are preserved unless a documented improvement is approved;
- project-specific runtime versions are no longer supplied implicitly by mise;
- Homebrew contains only declared native-app or reviewed exception packages;
- mise and chezmoi are not required at runtime;
- no secret value or private key is tracked by Git or embedded in a Nix store derivation;
- SSH and Git signing use 1Password-managed keys;
- unattended services, if any, obtain secrets without interactive 1Password unlock through the scoped sops-nix design;
- update, build, activation, reboot, and rollback paths have been exercised;
- the old dotfiles repository can be archived without losing required behavior.

## 13. Authoritative references

- Lix installation and compatibility: <https://lix.systems/install/>
- nix-darwin: <https://github.com/nix-darwin/nix-darwin>
- Home Manager: <https://nix-community.github.io/home-manager/>
- nix-homebrew: <https://github.com/zhaofengli/nix-homebrew>
- 1Password CLI secret injection: <https://developer.1password.com/docs/cli/secrets-scripts>
- 1Password SSH Agent: <https://developer.1password.com/docs/ssh/agent/>
- sops-nix: <https://github.com/Mic92/sops-nix>
- Node.js release status: <https://nodejs.org/en/about/previous-releases>
