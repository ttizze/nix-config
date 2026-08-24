{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.12.5";
  artifacts = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-bf39emxIw23pYJFPtDubnilRU8J63BUeES8MUMpbhjw=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-HuF3QbP83r7XzLFes7PclqVTbret1Y+A0kC7ToQo2M8=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-0ghrsoAbN9XIeOADH6CR33SiSpC5P+nTMgHxWx6EuJE=";
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
