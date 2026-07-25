# Nix-managed codex-acp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide `@agentclientprotocol/codex-acp` 1.1.7 through Home Manager so Buzz can use it without a mutable private npm install.

**Architecture:** A local `buildNpmPackage` derivation pins the published npm package and wraps its JavaScript entrypoint with a private `nodejs_24` interpreter. The existing overlay exposes the derivation to flake outputs, checks, and `home.packages`, while package tests enforce that no `node`, `npm`, or `npx` binary leaks into the result.

**Tech Stack:** Nix flakes, Home Manager, `buildNpmPackage`, Node.js 24, Bash tests

## Global Constraints

- Package `@agentclientprotocol/codex-acp` version `1.1.7`.
- Do not add global `node`, `npm`, or `npx` commands.
- Keep the existing `codex` package and authentication files unchanged.
- Support `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`.
- Remove Buzz's mutable private npm copy only after the Nix generation is active.

---

### Task 1: Add failing package contracts

**Files:**
- Modify: `tests/packages.sh`
- Modify: `tests/home-manager.sh`
- Modify: `tests/eval.sh`
- Modify: `tests/structure.sh`

**Interfaces:**
- Consumes: existing flake package and Home Manager evaluation commands.
- Produces: contracts for `.#codex-acp`, version `1.1.7`, Home Manager membership, package source files, and absence of runtime-manager binaries.

- [ ] **Step 1: Write the failing tests**

Add a `nix build .#codex-acp` assertion to `tests/packages.sh`, require
`codex-acp-1.1.7` in `tests/home-manager.sh`, evaluate its version in
`tests/eval.sh`, and require its three package source files in
`tests/structure.sh`.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
nix develop --command bash tests/structure.sh
```

Expected: failure because `pkgs/codex-acp/default.nix` does not exist.

- [ ] **Step 3: Commit the failing contracts**

```bash
git add tests/packages.sh tests/home-manager.sh tests/eval.sh tests/structure.sh
git commit -m "test: require Nix-managed codex-acp"
```

### Task 2: Package and expose codex-acp

**Files:**
- Create: `pkgs/codex-acp/default.nix`
- Create: `pkgs/codex-acp/package.json`
- Create: `pkgs/codex-acp/package-lock.json`
- Modify: `flake.nix`
- Modify: `modules/home/packages.nix`

**Interfaces:**
- Consumes: `buildNpmPackage`, `makeWrapper`, and `nodejs_24`.
- Produces: `pkgs.codex-acp` with main program `$out/bin/codex-acp`.

- [ ] **Step 1: Create the pinned npm wrapper manifest**

`package.json` contains:

```json
{
  "name": "codex-acp-nix-wrapper",
  "version": "1.1.7",
  "private": true,
  "dependencies": {
    "@agentclientprotocol/codex-acp": "1.1.7"
  }
}
```

Generate the lock file with:

```bash
nix shell nixpkgs#nodejs_24 -c npm install --package-lock-only --ignore-scripts
```

- [ ] **Step 2: Add the derivation**

Use `buildNpmPackage`, copy `node_modules` under
`$out/lib/codex-acp`, and wrap
`node_modules/@agentclientprotocol/codex-acp/dist/index.js` with
`${nodejs_24}/bin/node`. Set `dontNpmBuild = true` and
`npmFlags = [ "--ignore-scripts" ]`.

- [ ] **Step 3: Expose the package**

Add `codex-acp = final.callPackage ./pkgs/codex-acp { };` to the overlay, expose
it from `packages` and `checks`, and add `codex-acp` to `home.packages`.

- [ ] **Step 4: Run package checks**

Run:

```bash
nix develop --command bash tests/packages.sh
nix develop --command bash tests/home-manager.sh
nix develop --command bash tests/eval.sh
nix develop --command bash tests/structure.sh
```

Expected: all four scripts exit 0 and `codex-acp --version` prints `1.1.7`.

- [ ] **Step 5: Commit the implementation**

```bash
git add pkgs/codex-acp flake.nix modules/home/packages.nix
git commit -m "feat: manage codex-acp with Nix"
```

### Task 3: Validate, activate, and switch Buzz

**Files:**
- No repository file changes.
- Remove after activation: `~/Library/Application Support/Buzz/node-tools`

**Interfaces:**
- Consumes: the committed Nix configuration and the Buzz 0.4.25 runtime doctor.
- Produces: an active Home Manager profile resolving `codex-acp` from Nix and a Buzz runtime catalog that marks Codex available.

- [ ] **Step 1: Run the complete core verification**

Run:

```bash
nix develop --command just check-core
```

Expected: exit 0.

- [ ] **Step 2: Build and activate the clean configuration**

Run:

```bash
nix develop --command just build
nix develop --command just apply
```

Expected: nix-darwin switches to the new generation.

- [ ] **Step 3: Verify the active command boundary**

Run:

```bash
command -v codex-acp
codex-acp --version
test -z "$(command -v node || true)"
test -z "$(command -v npm || true)"
test -z "$(command -v npx || true)"
```

Expected: `codex-acp` resolves under `/etc/profiles/per-user/tt/bin`, reports
`1.1.7`, and the three Node commands remain absent.

- [ ] **Step 4: Remove the mutable Buzz package and restart**

Use the managed Node npm command with Buzz's private prefix to uninstall
`@agentclientprotocol/codex-acp`, remove an empty private prefix if one remains,
then restart Buzz.

- [ ] **Step 5: Verify Buzz**

Open **Settings → Agents**, click **Check again**, and confirm Codex availability
is on. Confirm the private `node-tools/bin/codex-acp` path is absent and the
Nix-profile `codex-acp` remains executable.
