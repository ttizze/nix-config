# Agent instructions

- Enter the pinned environment with `nix develop` when direnv is unavailable.
- Discover supported commands with `just --list`.
- Run `just check` before reporting completion.
- Use `op run --env-file=.env.op -- <command>` only for commands that require secrets.
- Never write resolved secrets to the repository or the Nix store.
