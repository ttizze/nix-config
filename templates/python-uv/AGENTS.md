# Agent instructions

- This repository is Nix-managed.
- Do not run project toolchain commands in a bare shell.
- Do not assume `.envrc` is loaded in agent or non-interactive shells.
- When `IN_NIX_SHELL` is unset, run project commands with `nix develop --command <command>`.
- Nix owns Python 3.13 and the uv executable.
- uv owns Python dependencies and `.venv`; it must not download another Python interpreter.
- Commit both `flake.lock` and `uv.lock`.
- Use `just sync`, `just test`, and `just check`.
- Run secret-dependent commands through `op run --env-file=.env.op -- <command>`.
