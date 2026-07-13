{ username, ... }:
{
  imports = [
    ../../modules/home/packages.nix
    ../../modules/home/shell.nix
    ../../modules/home/git.nix
    ../../modules/home/terminal.nix
    ../../modules/home/ssh.nix
  ];

  home = {
    inherit username;
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
