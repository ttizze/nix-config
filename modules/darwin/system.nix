{ username, ... }:
{
  nix = {
    enable = true;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        username
      ];
    };
  };

  programs.zsh.enable = true;

  system = {
    primaryUser = username;
    stateVersion = 6;
  };

  users.users.${username}.home = "/Users/${username}";
}
