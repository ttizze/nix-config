{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    bun
    claude-code
    codex
    curl
    dcg
    eza
    fd
    ghq
    git
    gnupg
    htop
    jq
    nodejs_24
    pnpm
    ripgrep
    tree
    turso-cli
    wget
    yq-go
    inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
