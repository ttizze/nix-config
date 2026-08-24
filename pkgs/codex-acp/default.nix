{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs_24,
}:

buildNpmPackage rec {
  pname = "codex-acp";
  version = "1.6.2";

  src = ./.;

  npmDepsHash = "sha256-9h1DANa3fjSVc1AXT/u4S7q+lXHB385BhGSWC/DRvgc=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/codex-acp" "$out/bin"
    cp -R node_modules "$out/lib/codex-acp/"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/codex-acp" \
      --add-flags "$out/lib/codex-acp/node_modules/@agentclientprotocol/codex-acp/dist/index.js"

    runHook postInstall
  '';

  meta = {
    description = "ACP adapter for OpenAI Codex";
    homepage = "https://github.com/agentclientprotocol/codex-acp";
    license = lib.licenses.asl20;
    mainProgram = "codex-acp";
    platforms = lib.platforms.unix;
  };
}
