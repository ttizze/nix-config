{ pkgs }:
pkgs.writeShellApplication {
  name = "bex-cache-maintenance";
  runtimeInputs = with pkgs; [
    python3
    git
    coreutils
    findutils
    util-linux
  ];
  text = ''
    exec python3 ${./maintenance.py} "$@"
  '';
}
