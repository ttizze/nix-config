{ pkgs, username, ... }:
{
  imports = [ ../../modules/home/applications.nix ];

  home = {
    homeDirectory = "/Users/${username}";
    packages = with pkgs; [
      pinentry_mac
    ];
    sessionVariables.SSH_AUTH_SOCK = "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  };
}
