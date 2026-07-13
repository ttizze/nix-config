# Agent instructions

- Bun is the only JavaScript runtime and package manager for this project.
- Do not introduce global Node.js, npm, pnpm, Wrangler, or Vercel dependencies.
- Enter the environment with `nix develop` when direnv is unavailable.
- Use `just --list`, `just dev`, `just test`, and `just check`.
- Run secret-dependent commands through `op run --env-file=.env.op -- <command>`.
