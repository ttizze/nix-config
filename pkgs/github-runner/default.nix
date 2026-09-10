{
  lib,
  stdenv,
  stdenvNoCC,
  autoPatchelfHook,
  fetchurl,
  github-runner,
  nodeRuntimes ? [ "node24" ],
}:
let
  # Runner 2.337.0 still uses Node 20 for hashFiles(), independently of the
  # Node 24 action setting. Match src/Misc/externals.sh from that release.
  node20 = stdenvNoCC.mkDerivation {
    pname = "github-runner-internal-node";
    version = "20.20.2";
    src = fetchurl {
      url = "https://nodejs.org/dist/v20.20.2/node-v20.20.2-linux-x64.tar.xz";
      hash = "sha256-33cLKm8TDthifJeCyYj9qWafojiYMpphqHHjL5ZeAH0=";
    };
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 bin/node "$out/bin/node"
      install -Dm644 LICENSE "$out/share/doc/github-runner-internal-node/LICENSE"
      runHook postInstall
    '';
    meta = {
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };
in
(github-runner.override { inherit nodeRuntimes; }).overrideAttrs (old: {
  preCheck = old.preCheck + ''
    ln -s ${node20} _layout/externals/node20
  '';
  postInstall = old.postInstall + ''
    ln -s ${node20} "$out/lib/externals/node20"
  '';
  postInstallCheck = (old.postInstallCheck or "") + ''
    (
      runner_fixture="$(mktemp -d)"
      trap 'rm -rf "$runner_fixture"' EXIT
      cd "$runner_fixture"
      printf 'runner hash fixture\n' > input
      patterns=input "$out/lib/externals/node20/bin/node" \
        "$out/lib/github-runner/hashFiles" > stdout 2> stderr
      grep -Fxq '__OUTPUT__81d14e3c78ca5b2a7ee150217a061ce5bf90b65cb29a5105eb7b61c86d506d1c__OUTPUT__' stderr
    )
  '';
})
