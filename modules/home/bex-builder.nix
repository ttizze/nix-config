# remote-agent's build pair: the Mac sends Rust checks to the WSL PC as
# `bex-wsl`, and the WSL PC's Nix uses the Mac for aarch64-darwin builds. Both
# directions are SSH over iroh-ssh; each machine keeps its iroh and SSH keys in
# `stateDir`, outside the store, so endpoint IDs survive rebuilds.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = "${config.xdg.stateHome}/bex-nix-builder";
  iroh-ssh = "${pkgs.iroh-ssh}/bin/iroh-ssh";
  server = [
    iroh-ssh
    "server"
    "--persist"
    "--key-dir"
    "${stateDir}/iroh"
  ];
  macEndpoint = "77b74591b765a52438a7bad6deef8305250309b21fd88cb1035c65bbf10e3c7c";
  wslEndpoint = "4b6243f47b0c0c56f3d3d541d100b8a55ebc8c1d298528a697f151a0241de7ca";
  wslKnownHosts = pkgs.writeText "bex-wsl-known-hosts" ''
    ${wslEndpoint} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEQq7DEc4e3+BB5FL1SzKlxa/JztN7rh+2QZu6n1SmFN
  '';
  # Mac nix-daemon reached by root's Nix through the WSL loopback forward below.
  macBuilderPort = 22440;
in
lib.mkMerge [
  (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    launchd.agents.iroh-ssh = {
      enable = true;
      config = {
        ProgramArguments = server;
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${stateDir}/iroh-ssh.log";
        StandardErrorPath = "${stateDir}/iroh-ssh.log";
      };
    };

    programs.ssh.settings.bex-wsl = {
      HostName = wslEndpoint;
      User = "tizze";
      ProxyCommand = "${iroh-ssh} proxy %h";
      IdentityFile = "${stateDir}/ssh/id_ed25519";
      UserKnownHostsFile = "${wslKnownHosts}";
      IdentitiesOnly = true;
      IdentityAgent = "none";
      BatchMode = true;
      StrictHostKeyChecking = true;
      ConnectTimeout = 20;
      ServerAliveInterval = 15;
      ServerAliveCountMax = 3;
    };
  })

  (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    systemd.user.services = {
      iroh-ssh = {
        Unit = {
          Description = "SSH into this machine over iroh";
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = lib.escapeShellArgs server;
          Restart = "always";
          RestartSec = 3;
        };
        Install.WantedBy = [ "default.target" ];
      };

      # The build-hook SSH runs as root without this user's SSH config, so
      # the Mac is exposed as a loopback port instead of an iroh ProxyCommand.
      mac-nix-builder = {
        Unit.Description = "Loopback SSH port for the Mac Nix builder over iroh";
        Service = {
          ExecStart = lib.escapeShellArgs [
            "${pkgs.socat}/bin/socat"
            "TCP4-LISTEN:${toString macBuilderPort},bind=127.0.0.1,reuseaddr,fork"
            "EXEC:${iroh-ssh} proxy ${macEndpoint}"
          ];
          Restart = "always";
          RestartSec = 3;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };

    nix = {
      package = pkgs.nix;
      distributedBuilds = true;
      buildMachines = [
        {
          protocol = "ssh-ng";
          hostName = "127.0.0.1:${toString macBuilderPort}?remote-program=/run/current-system/sw/bin/nix-daemon";
          sshUser = "tt";
          sshKey = "${stateDir}/ssh/id_ed25519";
          systems = [ "aarch64-darwin" ];
          # base64 of the Mac's `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPnnVeJUAjEA6UCta0TgSVr4M5p4KdbToKl3jetrqGA9`.
          publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSVBublZlSlVBakVBNlVDdGEwVGdTVnI0TTVwNEtkYlRvS2wzamV0cnFHQTkK";
        }
      ];
      settings.builders-use-substitutes = true;
    };
  })
]
