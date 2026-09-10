{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.14.2";
  artifacts = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-sNEWxcp1z+bsQS67e9XzoYY2y04UQVUMqQ3VoDNUq0k=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-xpLLlE5D6sRo07/EmPvMCL3n/eIC+2zzTKPtEZFA0yI=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-VRRDQGC+PW3NsLj0ezXvdUqD0n6cRinygFL1rXPrdgM=";
    };
  };
  artifact = artifacts.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "dcg";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Dicklesworthstone/destructive_command_guard/releases/download/v${version}/dcg-${artifact.target}.tar.xz";
    inherit (artifact) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 dcg $out/bin/dcg
    runHook postInstall
  '';

  meta = {
    description = "Destructive command guard";
    homepage = "https://github.com/Dicklesworthstone/destructive_command_guard";
    license = lib.licenses.mit;
    platforms = builtins.attrNames artifacts;
    mainProgram = "dcg";
  };
}
