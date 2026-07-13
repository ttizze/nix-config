# Vercel recipe

Use this recipe on top of either the `bun` or `node-pnpm` template.

1. Add `vercel` as a project development dependency.
2. Commit the language lock file.
3. Add explicit `dev`, `check`, and `deploy` scripts to `package.json`.
4. Expose those scripts through the project `justfile`.
5. Put required Vercel secret references in `.env.op`.
6. Run deployment through `op run --env-file=.env.op -- <package-manager> run deploy`.

The Agent must not depend on `~/.bun/bin/vercel` or another global Vercel CLI.
