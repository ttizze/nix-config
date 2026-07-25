{ pkgs, ... }:
{
  home.packages = with pkgs; [
    claude-code
    circleback-cli
    codex
    codex-acp
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
