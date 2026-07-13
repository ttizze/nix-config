# Agent instructions

- Nix owns Python 3.13 and the uv executable.
- uv owns Python dependencies and `.venv`; it must not download another Python interpreter.
- Commit both `flake.lock` and `uv.lock`.
- Enter the environment with `nix develop` when direnv is unavailable.
- Use `just sync`, `just test`, and `just check`.
- Run secret-dependent commands through `op run --env-file=.env.op -- <command>`.
