# Nix-managed codex-acp

## Goal

Make `codex-acp` available to Buzz from the Home Manager profile without exposing
global `node`, `npm`, or `npx` commands and without relying on Buzz's mutable
app-data npm prefix.

## Constraints

- Keep `nix-config` as the source of truth for globally available commands.
- Package `@agentclientprotocol/codex-acp` version `1.1.7`; the pinned nixpkgs
  `codex-acp` is the incompatible `zed-industries/codex-acp` version `0.13.0`.
- Keep Node.js as an internal runtime dependency of the wrapper.
- Support the repository's Darwin and Linux systems.
- Preserve the existing Codex package and authentication files.

## Design

Add a local `buildNpmPackage` derivation under `pkgs/codex-acp/`. A minimal
wrapper package lock pins `@agentclientprotocol/codex-acp` to `1.1.7`. The
derivation installs the dependency tree under its output and exposes only a
`codex-acp` wrapper backed by `nodejs_24`.

Expose the derivation through the existing overlay, add it to `home.packages`,
and include it in flake packages and checks. Extend the package tests to require
`codex-acp` while continuing to reject globally exposed `node`, `npm`, and
`npx`.

After building and applying the Home Manager generation, uninstall the mutable
Buzz-private npm copy. Restart Buzz and verify that its runtime doctor reports
Codex as available while `codex-acp` resolves through the Nix profile.

## Verification

1. The new package-focused test fails before implementation.
2. `nix build .#codex-acp` succeeds and `codex-acp --version` reports `1.1.7`.
3. Repository core checks pass.
4. `just apply` activates the generation.
5. The plain shell resolves `codex-acp` but still does not resolve `node`,
   `npm`, or `npx`.
6. Buzz reports Codex available after its private npm package is removed.
