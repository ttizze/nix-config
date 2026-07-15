# Agent instructions

- This repository is Nix-managed.
- Do not run project toolchain commands in a bare shell.
- Do not assume `.envrc` is loaded in agent or non-interactive shells.
- When `IN_NIX_SHELL` is unset, run project commands with `nix develop --command <command>`.
- Apple owns the Xcode installation; `.xcode-version` records the required version.
- Nix owns Ruby, Bundler, XcodeGen, and just.
- Bundler owns Fastlane through `Gemfile.lock`.
- Use `just bootstrap`, `just generate`, `just test`, and `just check`.
- Run release commands through `just deploy`; never expose resolved secrets.
