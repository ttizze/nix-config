# Nix Configuration Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, publish, and activate a reproducible Lix + nix-darwin + Home Manager configuration for `tt` on the current Apple Silicon Mac, with standalone Home Manager outputs for Ubuntu CLI hosts.

**Architecture:** A plain flake pins unstable nixpkgs and the platform managers. nix-darwin owns macOS state and embeds Home Manager; Linux uses the same Home Manager modules directly. Nix owns CLI tools, nix-homebrew owns only required GUI casks, 1Password owns interactive secrets, and project runtimes will move to per-project flakes in a later plan.

**Tech Stack:** Lix, Nix flakes, nix-darwin, Home Manager, nix-homebrew, GitHub Actions, shell smoke tests.

## Global Constraints

- Work only in this new repository. Treat `~/.local/share/chezmoi` and `ttizze/dotfiles` as read-only migration sources.
- Never commit secrets, vault/item names, `op://` references, private keys, tokens, generated 1Password files, or machine backups.
- Preserve current Homebrew formulae, mise shims, and local runtimes until project-specific devShell migration is complete.
- Keep `homebrew.onActivation.cleanup = "none"` throughout this plan. Strict cleanup is a later-plan gate.
- Preserve the current private `~/.ssh/config` as `~/.ssh/config.local` before activation.
- Keep the existing SSH private key until a separate 1Password SSH key-rotation plan is executed.
- Use `nixpkgs-unstable` pinned by `flake.lock`; do not introduce flake-parts.
- Initial supported targets are `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`. Ubuntu requires systemd and sudo; rootless hosts are out of scope.

---

## Task 1: Install and verify Lix on the Mac

**Files:**

- No repository files changed.

- [ ] **Step 1: Prove Nix is not already active**

Run:

```bash
command -v nix && nix --version
test -d /nix
```

Expected before installation: both checks fail.

- [ ] **Step 2: Install Lix using the official multi-user installer**

Run:

```bash
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
```

Accept only the installer changes required for the multi-user daemon.

- [ ] **Step 3: Load the daemon profile and verify flakes**

Run:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
nix --version
nix flake metadata nixpkgs --no-write-lock-file
```

Expected: the version identifies Lix, and flake metadata resolves successfully.

- [ ] **Step 4: Record installer evidence outside Git**

Run:

```bash
mkdir -p "$HOME/.local/state/nix-config/bootstrap"
nix --version > "$HOME/.local/state/nix-config/bootstrap/lix-version.txt"
```

Do not add this state directory to the repository.

---

## Task 2: Create an evaluable flake and custom DCG package

**Files:**

- Create: `flake.nix`
- Create: `pkgs/dcg.nix`
- Create: `hosts/tinoMac-mini/default.nix`
- Create: `modules/darwin/system.nix`
- Create: `home/tt/common.nix`
- Create: `home/tt/darwin.nix`
- Create: `home/tt/linux.nix`
- Test: `flake.lock`

- [ ] **Step 1: Add the DCG binary package**

Create `pkgs/dcg.nix` with the fixed v0.6.5 release matrix:

```nix
{ lib, stdenvNoCC, fetchurl }:

let
  version = "0.6.5";
  artifacts = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-JytbHz5KOtw7hsBn9cAgqibKpLcTZk9n+yrY4QQRGtw=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-dGAczIawbsC06on7b6nlmksRXePNGIMH5qbrMFFaYy0=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-ISgSGxTFht02htrBFy8HTK3lXbZk52ahcUoFPchYjWA=";
    };
  };
  artifact = artifacts.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "dcg";
  inherit version;
  src = fetchurl {
    url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${version}/dcg-${artifact.target}.tar.gz";
    inherit (artifact) hash;
  };
  sourceRoot = ".";
  installPhase = ''
    runHook preInstall
    install -Dm755 dcg $out/bin/dcg
    runHook postInstall
  '';
  meta = {
    description = "Destructive command guard";
    homepage = "https://github.com/Dicklesworthstone/destructive_command_guard";
    license = lib.licenses.mit;
    platforms = builtins.attrNames artifacts;
    mainProgram = "dcg";
  };
}
```

- [ ] **Step 2: Add the flake inputs and target outputs**

Create `flake.nix` with these exact interface decisions:

```nix
{
  description = "ttizze's reproducible macOS and Linux CLI environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager, nix-homebrew, homebrew-core, homebrew-cask, hermes-agent, ... }:
    let
      username = "tt";
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      overlay = final: prev: { dcg = final.callPackage ./pkgs/dcg.nix { }; };
      allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [ "claude-code" ];
      mkPkgs = system: import nixpkgs {
        inherit system;
        overlays = [ overlay ];
        config.allowUnfreePredicate = allowUnfreePredicate;
      };
      mkLinuxHome = system: home-manager.lib.homeManagerConfiguration {
        pkgs = mkPkgs system;
        extraSpecialArgs = { inherit inputs username; };
        modules = [ ./home/tt/common.nix ./home/tt/linux.nix ];
      };
    in {
      darwinConfigurations.tinoMac-mini = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs username overlay allowUnfreePredicate; };
        modules = [
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          ./hosts/tinoMac-mini
        ];
      };

      homeConfigurations = {
        "tt@linux-aarch64" = mkLinuxHome "aarch64-linux";
        "tt@linux-x86_64" = mkLinuxHome "x86_64-linux";
      };

      packages = forAllSystems (system: let pkgs = mkPkgs system; in { inherit (pkgs) dcg; default = pkgs.dcg; });
      checks = forAllSystems (system: let pkgs = mkPkgs system; in {
        dcg = pkgs.dcg;
      });
      formatter = forAllSystems (system: (mkPkgs system).nixfmt-rfc-style);
    };
}
```

- [ ] **Step 3: Add the minimum Darwin host module**

Create `hosts/tinoMac-mini/default.nix`:

```nix
{ inputs, username, overlay, allowUnfreePredicate, ... }:
{
  imports = [ ../../modules/darwin/system.nix ];
  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    overlays = [ overlay ];
    config.allowUnfreePredicate = allowUnfreePredicate;
  };
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    extraSpecialArgs = { inherit inputs username; };
    users.${username}.imports = [ ../../home/tt/common.nix ../../home/tt/darwin.nix ];
  };
}
```

Create `modules/darwin/system.nix`:

```nix
{ username, ... }:
{
  nix = {
    enable = true;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" username ];
    };
  };
  programs.zsh.enable = true;
  system = {
    primaryUser = username;
    stateVersion = 6;
  };
  users.users.${username}.home = "/Users/${username}";
}
```

- [ ] **Step 4: Add minimal Home Manager entry files**

Create `home/tt/common.nix`:

```nix
{ pkgs, username, ... }:
{
  home = {
    inherit username;
    stateVersion = "26.05";
    packages = [ pkgs.dcg ];
  };
  programs.home-manager.enable = true;
}
```

Create `home/tt/darwin.nix`:

```nix
{ username, ... }:
{
  home.homeDirectory = "/Users/${username}";
}
```

Create `home/tt/linux.nix`:

```nix
{ username, ... }:
{
  home.homeDirectory = "/home/${username}";
}
```

- [ ] **Step 5: Lock, format, and evaluate all output names**

Run:

```bash
nix flake lock
nix fmt
nix flake show
nix eval .#darwinConfigurations.tinoMac-mini.config.system.build.toplevel.drvPath
nix eval .#homeConfigurations."tt@linux-aarch64".activationPackage.drvPath
nix eval .#homeConfigurations."tt@linux-x86_64".activationPackage.drvPath
nix build .#packages.aarch64-darwin.dcg
./result/bin/dcg --version
```

Expected: all outputs evaluate, and DCG prints `0.6.5`.

- [ ] **Step 6: Commit the evaluable skeleton**

Run:

```bash
git add flake.nix flake.lock pkgs hosts modules/darwin/system.nix home
git commit -m "feat: add cross-platform Nix flake foundation"
```

---

## Task 3: Implement the shared Home Manager environment

**Files:**

- Create: `modules/home/packages.nix`
- Create: `modules/home/shell.nix`
- Create: `modules/home/git.nix`
- Create: `modules/home/terminal.nix`
- Create: `modules/home/ssh.nix`
- Create: `files/p10k.zsh`
- Create: `files/wezterm.lua`
- Modify: `home/tt/common.nix`
- Modify: `home/tt/darwin.nix`
- Modify: `home/tt/linux.nix`

- [ ] **Step 1: Import only portable CLI packages**

Create `modules/home/packages.nix`:

```nix
{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    bun
    claude-code
    codex
    curl
    dcg
    eza
    fd
    ghq
    git
    gnupg
    htop
    jq
    nodejs_24
    pnpm
    ripgrep
    tree
    turso-cli
    wget
    yq-go
    inputs.hermes-agent.packages.${pkgs.system}.default
  ];
}
```

If the Hermes input exposes a differently named package on a target, inspect `nix flake show github:NousResearch/hermes-agent` and select its actual default package; do not wrap the existing mutable checkout.

- [ ] **Step 2: Mechanically import the current prompt and WezTerm behavior**

Run these read-only source transforms:

```bash
mkdir -p files
awk 'NF && $0 !~ /^[[:space:]]*#/' "$HOME/.p10k.zsh" > files/p10k.zsh
cp "$HOME/.wezterm.lua" files/wezterm.lua
```

Review both files for absolute home paths, tokens, email addresses, and host-specific private data before staging. The generated p10k file may contain prompt behavior only.

- [ ] **Step 3: Implement zsh without legacy runtime initializers**

Create `modules/home/shell.nix`:

```nix
{ pkgs, ... }:
{
  home.file.".p10k.zsh".source = ../../files/p10k.zsh;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      path = "$HOME/.zsh_history";
      size = 10000;
      save = 10000;
      ignoreDups = true;
      share = true;
    };
    shellAliases = {
      br = "bun run";
      brd = "bun run dev";
      gc = "git commit";
      ls = "eza --icons=auto";
      ll = "eza -lah --icons=auto --git";
      tree = "eza --tree --icons=auto";
    };
    plugins = [{
      name = "powerlevel10k";
      src = pkgs.zsh-powerlevel10k;
      file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    }];
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };
    initContent = ''
      [[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

      repo() {
        local destination
        destination="$(ghq root)/github.com/$1"
        [[ -d "$destination" ]] && cd "$destination"
      }

      fkill() {
        local pid
        pid="$(ps -ef | sed 1d | fzf -m | awk '{print $2}')"
        [[ -n "$pid" ]] && echo "$pid" | xargs kill -9
      }

      gq() {
        local branch
        git branch --merged | sed -e '/^[*]/d' -e '/main/d' -e '/master/d' | while IFS= read -r branch; do
          [[ -n "$branch" ]] && git branch -d "$branch"
        done
      }

      gpm() {
        git pull --prune origin main
      }
    '';
  };
}
```

Do not source Homebrew, mise, Bun, pnpm, Cargo, Hermes, or Turso environment fragments here. Nix must provide the managed commands.

- [ ] **Step 4: Implement portable Git and GitHub CLI configuration**

Create `modules/home/git.nix`:

```nix
{
  programs = {
    git = {
      enable = true;
      settings = {
        user = {
          name = "tomolld";
          email = "tomoki2757@gmail.com";
        };
        init.defaultBranch = "main";
        fetch.prune = true;
        credential."https://github.com".helper = "!gh auth git-credential";
        credential."https://gist.github.com".helper = "!gh auth git-credential";
      };
    };
    gh = {
      enable = true;
      gitCredentialHelper.enable = true;
      settings.git_protocol = "https";
    };
  };
}
```

Do not migrate the existing machine-specific `safe.directory` entries or a hard-coded `/opt/homebrew/bin/gh` path.

- [ ] **Step 5: Implement terminal tools through their Home Manager modules**

Create `modules/home/terminal.nix`:

```nix
{
  programs = {
    bat.enable = true;
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };
    tmux.enable = true;
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
```

- [ ] **Step 6: Make SSH includes explicit and secrets external**

Create `modules/home/ssh.nix`:

```nix
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "~/.ssh/1Password/config" "~/.ssh/config.local" ];
    matchBlocks."*" = {
      serverAliveInterval = 60;
      serverAliveCountMax = 3;
      addKeysToAgent = "yes";
    };
  };
}
```

The first include may be absent until 1Password creates it; the second is private local state. Neither target is committed.

- [ ] **Step 7: Wire shared and platform-specific Home Manager modules**

Replace `home/tt/common.nix` with:

```nix
{ pkgs, username, ... }:
{
  imports = [
    ../../modules/home/packages.nix
    ../../modules/home/shell.nix
    ../../modules/home/git.nix
    ../../modules/home/terminal.nix
    ../../modules/home/ssh.nix
  ];
  home = {
    inherit username;
    stateVersion = "26.05";
  };
  programs.home-manager.enable = true;
}
```

Replace `home/tt/darwin.nix` with:

```nix
{ pkgs, username, ... }:
{
  home = {
    homeDirectory = "/Users/${username}";
    packages = [ pkgs.blueutil ];
    sessionVariables.SSH_AUTH_SOCK = "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  };
  home.file.".wezterm.lua".source = ../../files/wezterm.lua;
  programs.zsh.profileExtra = ''
    [[ -r ~/.orbstack/shell/init.zsh ]] && source ~/.orbstack/shell/init.zsh
  '';
}
```

Keep `home/tt/linux.nix` limited to `home.homeDirectory = "/home/${username}";`. Headless Ubuntu must use an explicitly forwarded SSH agent or service credential and must not assume a local 1Password socket.

- [ ] **Step 8: Format, evaluate, and commit Home Manager behavior**

Run:

```bash
nix fmt
nix eval .#darwinConfigurations.tinoMac-mini.config.home-manager.users.tt.home.packages --apply builtins.length
nix eval .#homeConfigurations."tt@linux-aarch64".activationPackage.drvPath
nix eval .#homeConfigurations."tt@linux-x86_64".activationPackage.drvPath
git diff --check
git add modules/home home/tt files
git commit -m "feat: manage shared user environment with Home Manager"
```

---

## Task 4: Complete nix-darwin and nix-homebrew ownership

**Files:**

- Modify: `modules/darwin/system.nix`
- Create: `modules/darwin/defaults.nix`
- Create: `modules/darwin/homebrew.nix`
- Modify: `hosts/tinoMac-mini/default.nix`

- [ ] **Step 1: Add garbage collection and store optimization**

Extend `modules/darwin/system.nix` with:

```nix
nix = {
  enable = true;
  settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" username ];
  };
  gc = {
    automatic = true;
    interval = [{ Weekday = 7; Hour = 3; Minute = 15; }];
    options = "--delete-older-than 30d";
  };
  optimise.automatic = true;
};
```

Keep the existing `programs.zsh`, `system.primaryUser`, `system.stateVersion`, and user-home declarations.

- [ ] **Step 2: Manage only verified macOS defaults**

Create `modules/darwin/defaults.nix`:

```nix
{
  system.defaults.finder.FXPreferredViewStyle = "Nlsv";
}
```

Do not add opinionated keyboard, Dock, trackpad, security, or power defaults without measuring the current state and approving the behavior.

- [ ] **Step 3: Pin Homebrew repositories and declare the required casks**

Create `modules/darwin/homebrew.nix`:

```nix
{ inputs, username, ... }:
{
  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    user = username;
    autoMigrate = true;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
  };

  homebrew = {
    enable = true;
    casks = [ "1password" "1password-cli" "orbstack" ];
    onActivation = {
      autoUpdate = false;
      upgrade = true;
      cleanup = "none";
    };
  };
}
```

The existing 1Password application will be adopted into Homebrew before activation. Other manually installed applications remain outside Nix ownership.

- [ ] **Step 4: Import the new Darwin modules**

Change the host import list to:

```nix
imports = [
  ../../modules/darwin/system.nix
  ../../modules/darwin/defaults.nix
  ../../modules/darwin/homebrew.nix
];
```

- [ ] **Step 5: Build the complete Darwin closure without activation**

Run:

```bash
nix fmt
nix flake check --no-build
nix build .#darwinConfigurations.tinoMac-mini.system
```

Expected: `result` points to the built nix-darwin system closure.

- [ ] **Step 6: Commit platform ownership**

Run:

```bash
git add modules/darwin hosts/tinoMac-mini
git commit -m "feat: manage macOS and Homebrew with nix-darwin"
```

---

## Task 5: Add safe operational scripts, tests, CI, and documentation

**Files:**

- Create: `bin/backup`
- Create: `bin/build`
- Create: `bin/apply`
- Create: `bin/update`
- Create: `tests/smoke.sh`
- Create: `.github/workflows/check.yml`
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Add a local-state backup script**

Create executable `bin/backup` that uses `set -euo pipefail`, creates a timestamped directory under `${XDG_STATE_HOME:-$HOME/.local/state}/nix-config/backups`, and copies these paths when present:

```text
~/.zshrc
~/.zprofile
~/.zshenv
~/.p10k.zsh
~/.gitconfig
~/.wezterm.lua
~/.ssh/config
~/.config/nix-darwin
```

End by running `find "$destination" -type f -exec shasum -a 256 {} \; > "$destination/SHA256SUMS"` and print the absolute destination. Never copy `~/.ssh` recursively.

- [ ] **Step 2: Add target-aware build and apply scripts**

Create executable `bin/build`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "$(uname -s):$(uname -m)" in
  Darwin:arm64) exec nix build .#darwinConfigurations.tinoMac-mini.system ;;
  Linux:aarch64) exec nix build '.#homeConfigurations."tt@linux-aarch64".activationPackage' ;;
  Linux:x86_64) exec nix build '.#homeConfigurations."tt@linux-x86_64".activationPackage' ;;
  *) echo "unsupported platform: $(uname -s):$(uname -m)" >&2; exit 1 ;;
esac
```

Create executable `bin/apply`. It must call `bin/build` first. On Darwin it uses installed `darwin-rebuild` when available, otherwise runs:

```bash
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#tinoMac-mini
```

On Linux it executes the activation package selected by architecture:

```bash
"$(readlink result)/activate"
```

- [ ] **Step 3: Add a conservative update script**

Create executable `bin/update`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
nix flake update
nix fmt
nix flake check --no-build
"$PWD/bin/build"
```

The lockfile update is reviewed and committed separately; the script must not auto-commit or activate.

- [ ] **Step 4: Add a smoke test covering the managed user contract**

Create executable `tests/smoke.sh` that asserts these commands exist:

```text
bat bun claude codex curl dcg direnv eza fd fzf gh ghq git gpg hermes htop jq node npm pnpm rg tmux tree turso wget yq zoxide zsh
```

It must also assert:

```bash
node --version | grep -Eq '^v24\.'
git config --global --get init.defaultBranch | grep -qx main
git config --global --get fetch.prune | grep -qx true
zsh -lic 'typeset -f repo fkill gq gpm >/dev/null'
```

- [ ] **Step 5: Add Linux-build and Darwin-evaluation CI**

Create `.github/workflows/check.yml` with `push` and `pull_request` triggers. Use `samueldr/lix-gha-installer-action@a0fee77b2a98bb7c5c0ed7ae6d6ad4903dbdad0d`, then run on `ubuntu-latest`:

```bash
nix flake check --no-build
nix build '.#homeConfigurations."tt@linux-x86_64".activationPackage'
```

Add a `macos-14` job that runs:

```bash
nix eval .#darwinConfigurations.tinoMac-mini.config.system.build.toplevel.drvPath
```

- [ ] **Step 6: Document ownership, bootstrap, rollback, and secret rules**

Create `README.md` containing:

- ownership table: nix-darwin = macOS/system, Home Manager = user/CLI/dotfiles, nix-homebrew = three casks, 1Password = interactive secrets, project flakes = project runtimes;
- Mac bootstrap: install Lix, clone, run `bin/backup`, preserve SSH config locally, adopt 1Password, run `bin/apply`;
- Ubuntu bootstrap: install Lix, clone, select architecture, run `bin/apply`;
- update procedure: `bin/update`, review `flake.lock`, commit, apply;
- rollback procedure: `sudo darwin-rebuild --list-generations`, then `sudo darwin-rebuild --rollback` or activate an explicit generation;
- secret examples using `op run --env-file=.env.op -- command` and `op inject -i template -o generated`, with no real vault/item names;
- explicit statement that sops-nix is deferred until an unattended service needs decryption;
- migration status and the gate preventing Homebrew cleanup until project devShell migrations finish.

Create `.gitignore`:

```gitignore
result
result-*
.direnv/
*.hm-backup
*.local
.env
.env.*
!.env.example
```

- [ ] **Step 7: Validate scripts and documentation**

Run:

```bash
chmod +x bin/backup bin/build bin/apply bin/update tests/smoke.sh
shellcheck bin/backup bin/build bin/apply bin/update tests/smoke.sh
nix fmt
nix flake check --no-build
git diff --check
```

If `shellcheck` is unavailable, run it ephemerally with `nix shell nixpkgs#shellcheck -c shellcheck ...`.

- [ ] **Step 8: Commit the operational layer**

Run:

```bash
git add .github .gitignore README.md bin tests flake.lock
git commit -m "feat: add safe bootstrap and verification workflow"
```

---

## Task 6: Prove the public repository is safe and publish it

**Files:**

- Inspect: all tracked files
- Create remotely: `github.com/ttizze/nix-config`

- [ ] **Step 1: Search for secret material and private runtime state**

Run:

```bash
git grep -nE '(op://|BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]+|sk-[A-Za-z0-9]|AKIA[0-9A-Z]{16}|password[[:space:]]*=|token[[:space:]]*=)' -- . ':!docs/superpowers/specs/*' ':!docs/superpowers/plans/*'
git ls-files | grep -E '(^|/)(\.env|id_[^/]+|config\.local|secrets?|backups?)(/|$)'
```

Expected: no matches. Documentation may mention generic secret formats but must contain no real reference.

- [ ] **Step 2: Inspect all absolute paths and identity strings**

Run:

```bash
git grep -n '/Users/'
git grep -nE '(gmail\.com|@)' -- '*.nix' '*.sh' README.md
```

Allow only the intentional username/home path, Git identity, fixed 1Password socket, and public repository metadata. Remove everything else that reveals unrelated local state.

- [ ] **Step 3: Run the complete pre-publication verification**

Run:

```bash
nix fmt -- --check .
nix flake check --no-build
nix build .#darwinConfigurations.tinoMac-mini.system
nix build '.#homeConfigurations."tt@linux-x86_64".activationPackage'
nix build '.#homeConfigurations."tt@linux-aarch64".activationPackage'
git diff --check
git status --short
```

Expected: all builds succeed and the worktree is clean after committing any formatting changes.

- [ ] **Step 4: Create and push the new public repository**

Run:

```bash
gh auth status
gh repo create ttizze/nix-config --public --source=. --remote=origin --push
gh repo view ttizze/nix-config --json nameWithOwner,visibility,url,defaultBranchRef
```

Expected: owner/name is `ttizze/nix-config`, visibility is `PUBLIC`, and the default branch is `main`.

---

## Task 7: Back up the Mac and activate the configuration

**Files:**

- Local-only state: `~/.local/state/nix-config/backups/*`
- Local-only state: `~/.ssh/config.local`
- Generated state: nix-darwin and Home Manager profiles

- [ ] **Step 1: Create and verify the pre-activation backup**

Run:

```bash
backup_path="$(bin/backup)"
test -f "$backup_path/SHA256SUMS"
(cd "$backup_path" && shasum -a 256 -c SHA256SUMS)
```

Expected: every copied file validates.

- [ ] **Step 2: Preserve the private SSH configuration as a local include**

Run:

```bash
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if test -f "$HOME/.ssh/config" && ! test -f "$HOME/.ssh/config.local"; then
  cp "$HOME/.ssh/config" "$HOME/.ssh/config.local"
  chmod 600 "$HOME/.ssh/config.local"
fi
```

Inspect `~/.ssh/config.local` and ensure it is not inside the repository.

- [ ] **Step 3: Bring the existing 1Password app under declared cask ownership**

Run:

```bash
brew install --cask --adopt 1password
brew list --cask | grep -qx 1password
brew list --cask | grep -qx 1password-cli
brew list --cask | grep -qx orbstack
```

If Homebrew reports the app is already owned, treat that as success. Do not delete the app or its data.

- [ ] **Step 4: Build once more immediately before activation**

Run:

```bash
bin/build
```

Expected: no evaluation or build failure.

- [ ] **Step 5: Activate the first nix-darwin generation**

Run:

```bash
bin/apply
```

Expected: nix-darwin switches `tinoMac-mini`, embeds the `tt` Home Manager profile, and preserves conflicting files with the `.hm-backup` suffix.

- [ ] **Step 6: Open a clean login shell and run smoke tests**

Run:

```bash
/bin/zsh -lic 'exec "$PWD/tests/smoke.sh"'
```

Also run:

```bash
command -v node bun codex claude hermes turso dcg
which -a node bun codex claude hermes turso dcg
echo "$SSH_AUTH_SOCK"
test "$SSH_AUTH_SOCK" = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
ssh -G github.com >/dev/null
defaults read com.apple.finder FXPreferredViewStyle | grep -qx Nlsv
brew list --formula
```

The first path for managed commands must be a Nix profile. Existing Homebrew formulae may still appear later in PATH and remain installed during migration.

- [ ] **Step 7: Verify the generation and rollback surface**

Run:

```bash
sudo darwin-rebuild --list-generations
readlink /run/current-system
ls -l "$HOME/.local/state/nix/profiles/home-manager"* 2>/dev/null || true
```

Record the active generation number and its store path. Do not execute a rollback unless activation validation fails.

---

## Task 8: Record verified state and close the foundation migration

**Files:**

- Create: `docs/verification/2026-07-13-macos-foundation.md`
- Modify if required: `README.md`

- [ ] **Step 1: Create a verification record with no secrets**

Create `docs/verification/2026-07-13-macos-foundation.md` containing:

- Lix version;
- active nix-darwin generation and store path;
- the three successfully evaluated target outputs;
- smoke-test command and pass result;
- cask ownership result;
- confirmation that SSH configuration is an include-only public file plus private local files;
- confirmation that Homebrew cleanup remains `none`;
- explicit pending gates: reboot validation, project devShell migrations, strict Homebrew cleanup, and 1Password SSH key rotation.

Do not paste package paths containing unrelated usernames, SSH hosts, token values, vault names, or item names.

- [ ] **Step 2: Re-run secret and configuration checks after activation**

Run:

```bash
git grep -nE '(op://|BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]+|sk-[A-Za-z0-9]|AKIA[0-9A-Z]{16})' -- . ':!docs/superpowers/specs/*' ':!docs/superpowers/plans/*'
nix flake check --no-build
bin/build
tests/smoke.sh
git diff --check
```

Expected: no secret matches and all verification commands succeed.

- [ ] **Step 3: Commit and push the verified foundation**

Run:

```bash
git add docs/verification README.md
git commit -m "docs: record macOS Nix foundation verification"
git push origin main
gh run list --repo ttizze/nix-config --limit 5
```

Wait for the pushed CI workflow and verify both Linux build and Darwin evaluation jobs pass.

- [ ] **Step 4: Perform the reboot gate only with explicit user approval**

Before rebooting, report the active generation and backup path to the user. After approval, reboot macOS, then run:

```bash
sudo darwin-rebuild --list-generations
tests/smoke.sh
ssh -G github.com >/dev/null
brew list --cask
```

If any test fails, activate the previous generation and restore only the affected file from the verified backup.

---

## Follow-on Plans Required Before Strict Cleanup

1. Add a flake and `.envrc` to each active project; verify each project’s tests and build inside its devShell.
2. Remove the matching Homebrew formula or mise runtime only after that project migration passes.
3. After all formula and runtime migrations plus a successful reboot, change `homebrew.onActivation.cleanup` from `"none"` to `"zap"`, build, review the deletion set, and activate.
4. Move Git/SSH signing and authentication to 1Password SSH Agent in a separate key-rotation plan; keep the current local key until remote access is verified.
5. Introduce sops-nix only when a concrete unattended service cannot use an interactive 1Password session or injected service credential.
