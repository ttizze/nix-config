{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.14.4";
  artifacts = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-twT+AZC/7sUbwmSlc/o9YgWQKGsrK2OyyiKTqiSq0BM=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-DLak6FG7FiaAfhxfv9bVZSdTg6diQihnj4WFcL9Bbm8=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-Cdr3ZeIUV6dW5pzJ+LzkFjWDbGuVj1snx6amo3bL3iE=";
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
