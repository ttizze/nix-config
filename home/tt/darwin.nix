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

  launchd.agents.codex-model-router = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.codex-model-router}/bin/codex-model-router"
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        USER = username;
      };
      StandardOutPath = "/Users/${username}/Library/Logs/codex-model-router.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/codex-model-router.error.log";
    };
  };
}
