{ pkgs, ... }:
{
  home.packages = with pkgs; [
    claude-code
    circleback-cli
    codex
    curl
    dcg
    eza
    fd
    ghq
    gnupg
    htop
    jq
    ripgrep
    yq-go
  ];
}
