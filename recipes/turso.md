# Turso recipe

Turso is an additive service tool, not a runtime template.

1. Add `turso-cli` to the project's Nix development shell.
2. Keep schema and migration files in the project repository.
3. Put database URL and token secret references in `.env.op`.
4. Add explicit database and migration recipes to the project `justfile`.
5. Run authenticated operations through `op run --env-file=.env.op -- just <recipe>`.

The Agent must not depend on the Homebrew Turso formula or a global login state.
