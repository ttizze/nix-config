{ pkgs, username, ... }:
{
  home = {
    inherit username;
    stateVersion = "26.05";
    packages = [ pkgs.dcg ];
  };

  programs.home-manager.enable = true;
}
