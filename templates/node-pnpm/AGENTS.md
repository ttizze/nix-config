# Agent instructions

- Node.js and pnpm are the only JavaScript runtime and package manager for this project.
- Do not introduce Bun or global deployment CLIs.
- Enter the environment with `nix develop` when direnv is unavailable.
- Use `just --list`, `just dev`, `just test`, and `just check`.
- Run secret-dependent commands through `op run --env-file=.env.op -- <command>`.
