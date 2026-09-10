{
  lib,
  buildNpmPackage,
  makeWrapper,
  nodejs_24,
}:

buildNpmPackage rec {
  pname = "circleback-cli";
  version = "0.3.1";

  src = ./.;

  npmDepsHash = "sha256-GaqyY6iK+Qw5PNFbORLpmVEYhA+ovutFyzvjy0pJ8qw=";
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/circleback-cli" "$out/bin"
    cp -R node_modules "$out/lib/circleback-cli/"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/cb" \
      --add-flags "$out/lib/circleback-cli/node_modules/@circleback/cli/dist/index.js"
    ln -s cb "$out/bin/circleback"

    runHook postInstall
  '';

  meta = {
    description = "CLI for searching Circleback meetings, transcripts, email, and calendar context";
    homepage = "https://circleback.ai";
    license = lib.licenses.mit;
    mainProgram = "cb";
    platforms = lib.platforms.unix;
  };
}
