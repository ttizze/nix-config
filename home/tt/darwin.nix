{ pkgs, username, ... }:
{
  home = {
    homeDirectory = "/Users/${username}";
    packages = [ pkgs.blueutil ];
    sessionVariables.SSH_AUTH_SOCK = "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  };

  home.file.".wezterm.lua".source = ../../files/wezterm.lua;

  programs.zsh.profileExtra = ''
    [[ -r ~/.orbstack/shell/init.zsh ]] && source ~/.orbstack/shell/init.zsh
  '';
}
