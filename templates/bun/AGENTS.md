# Agent instructions

- This repository is Nix-managed.
- Do not run project toolchain commands in a bare shell.
- Do not assume `.envrc` is loaded in agent or non-interactive shells.
- When `IN_NIX_SHELL` is unset, run project commands with `nix develop --command <command>`.
- Bun is the only JavaScript runtime and package manager for this project.
- Do not introduce global Node.js, npm, pnpm, Wrangler, or Vercel dependencies.
- Use `just --list`, `just dev`, `just test`, and `just check`.
- Run secret-dependent commands through `op run --env-file=.env.op -- <command>`.
