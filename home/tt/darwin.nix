{
  config,
  lib,
  pkgs,
  username,
  ...
}:
{
  imports = [
    ../../modules/home/applications.nix
    ../../modules/home/bex-builder.nix
  ];

  home = {
    homeDirectory = "/Users/${username}";
    # Keep Claude settings editable; changes remain visible in agent-config's Git diff.
    file.".claude/settings.json".source = lib.mkForce (
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/ghq/github.com/ttizze/agent-config/claude/settings.json"
    );
    packages = with pkgs; [
      pinentry_mac
    ];
    sessionVariables.SSH_AUTH_SOCK = "/Users/${username}/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  };

}
