{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.15.3";
  artifacts = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-UKGlB2IpnH5LXrrz+TL0UGbI58hqHV1BmwG6vR4mmNc=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-Nhdlh371/Cqonj0HsYmkq7pDaEQRJftfZ7VyjSblsnE=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-3H3OyWefdKw+aZCVl3HKDIQWjrpljv9k/p5j+ReoTMQ=";
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
