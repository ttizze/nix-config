{ config, inputs, username, ... }:
{
  nix-homebrew = {
    enable = true;
    enableRosetta = false;
    user = username;
    autoMigrate = true;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "nikitabobko/homebrew-tap" = inputs.homebrew-aerospace;
    };
  };

  homebrew = {
    enable = true;
    taps = builtins.attrNames config.nix-homebrew.taps;
    brews = [ "blueutil" ];
    casks = [
      "1password"
      "1password-cli"
      "aerospace"
      "chatgpt"
      "claude"
      "cmux"
      "discord"
      "google-chrome"
      "karabiner-elements"
      "logi-options+"
      "zed"
    ];
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
  };
}
