{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "codex-model-router";
  version = "0.1.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python -m unittest -v test_router.py
    runHook postCheck
  '';
  doCheck = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/codex-model-router" "$out/bin"
    cp router.py "$out/lib/codex-model-router/router.py"
    makeWrapper ${python3}/bin/python "$out/bin/codex-model-router" \
      --add-flags "$out/lib/codex-model-router/router.py"
    runHook postInstall
  '';

  meta = {
    description = "Loopback Responses router for native Codex and selected OpenCode Zen models";
    license = lib.licenses.mit;
    mainProgram = "codex-model-router";
    platforms = lib.platforms.unix;
  };
}
