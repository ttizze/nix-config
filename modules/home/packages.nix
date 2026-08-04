{ pkgs, ... }:
{
  home.packages = with pkgs; [
    claude-agent-acp
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
