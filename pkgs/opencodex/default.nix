{
  lib,
  buildNpmPackage,
  bun,
  fetchurl,
  makeWrapper,
  nodejs_24,
}:

buildNpmPackage rec {
  pname = "opencodex";
  version = "2.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@bitkyc08/opencodex/-/opencodex-${version}.tgz";
    hash = "sha256-Ak4vx/NM/3pYcodzbG3ZuFkOkOaW/jeSG7kPkdQmqJo=";
  };

  sourceRoot = "package";

  # The published npm tarball does not include its lockfile. Keep the exact
  # dependency graph in this repository so Nix can fetch it reproducibly.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # OpenCodex bundles Bun for npm installs. Nix supplies Bun instead, so build
  # without lifecycle scripts and point the launcher at the Nix-managed binary.
  npmDepsHash = "sha256-HT1YvZIxTC/IesQNvmqLU3qI4/sfhjVUOB3Xi8ZKpOg=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/opencodex" "$out/bin"
    cp -R . "$out/lib/opencodex/"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/ocx" \
      --add-flags "$out/lib/opencodex/bin/ocx.mjs" \
      --set OPENCODEX_BUN_PATH "${bun}/bin/bun"
    ln -s ocx "$out/bin/opencodex"

    runHook postInstall
  '';

  meta = {
    description = "Universal provider proxy for OpenAI Codex and Claude Code";
    homepage = "https://github.com/lidge-jun/opencodex";
    license = lib.licenses.mit;
    mainProgram = "ocx";
    platforms = lib.platforms.unix;
  };
}
