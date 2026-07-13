{ inputs, username, ... }:
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
    };
  };

  homebrew = {
    enable = true;
    brews = [ "blueutil" ];
    casks = [
      "1password"
      "1password-cli"
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
