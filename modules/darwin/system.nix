{ pkgs, username, ... }:
{
  nix = {
    enable = true;
    package = pkgs.lix;
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
    gc = {
      automatic = true;
      interval = [
        {
          Weekday = 7;
          Hour = 3;
          Minute = 15;
        }
      ];
      options = "--delete-older-than 30d";
    };
    optimise.automatic = true;
  };

  programs.zsh.enable = true;

  networking = {
    computerName = "tのMac mini";
    localHostName = "tinoMac-mini";
  };

  time.timeZone = "Asia/Tokyo";

  system = {
    primaryUser = username;
    stateVersion = 6;
  };

  users.users.${username}.home = "/Users/${username}";
}
