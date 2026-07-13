# Cloudflare recipe

Use this recipe on top of either the `bun` or `node-pnpm` template.

1. Add Wrangler to the project, never the global Mac environment:
   - Bun: `bun add --dev wrangler`
   - pnpm: `pnpm add --save-dev wrangler`
2. Commit the language lock file.
3. Add `dev`, `check`, and `deploy` scripts to `package.json`.
4. Expose those scripts through `just dev`, `just check`, and `just deploy`.
5. Put Cloudflare secret references in the tracked `.env.op` file.
6. Run deployment through `op run --env-file=.env.op -- <package-manager> run deploy`.

The Agent must use the project scripts and must not install or invoke a global Wrangler.
