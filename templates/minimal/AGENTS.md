# Agent instructions

- This repository is Nix-managed.
- Do not run project toolchain commands in a bare shell.
- Do not assume `.envrc` is loaded in agent or non-interactive shells.
- When `IN_NIX_SHELL` is unset, run project commands with `nix develop --command <command>`.
- Discover supported commands with `just --list`.
- Run `just check` before reporting completion.
- Use `op run --env-file=.env.op -- <command>` only for commands that require secrets.
- Never write resolved secrets to the repository or the Nix store.
