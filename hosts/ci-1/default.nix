{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  nixCiRepositories = [
    "agent-config"
    "nix-config"
  ];
  runtimeLibraries = with pkgs; [
    alsa-lib
    at-spi2-atk
    expat
    glib
    libxcomposite
    libxdamage
    libxfixes
    libxrandr
    libgbm
    libgcc.lib
    libxkbcommon
    nspr
    nss
    cups
    dbus
    libdrm
    libx11
    libxcb
    libxext
    pango
    cairo
    openssl
    zlib
    icu
    systemd
  ];
in
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "ci-1";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  swapDevices = [
    {
      device = "/swapfile";
      size = 4096;
    }
  ];
  system.stateVersion = "26.05";
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    max-jobs = 1;
    cores = 2;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  virtualisation.docker.enable = true;
  programs.nix-ld = {
    enable = true;
    libraries = runtimeLibraries;
  };
  fonts.packages = with pkgs; [
    liberation_ttf
    noto-fonts-cjk-sans
  ];
  environment.systemPackages = with pkgs; [
    git
    gh
    jq
    curl
  ];

  users.groups = {
    runner = { };
  }
  // lib.genAttrs nixCiRepositories (_: { });
  users.users = {
    root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDkpaLbtIXjBAOV3Rlm3R8iX4clIgPqMi3AcuvzZi4qk"
    ];
    runner = {
      isSystemUser = true;
      group = "runner";
      extraGroups = [ "docker" ];
    };
  }
  // lib.genAttrs nixCiRepositories (repo: {
    isSystemUser = true;
    group = repo;
  });
  systemd.tmpfiles.rules = [
    "d /var/lib/tsurumi-ci-work 0700 runner runner -"
  ]
  ++ map (repo: "d /var/lib/${repo}-ci-work 0700 ${repo} ${repo} -") nixCiRepositories;
  services.github-runners =
    lib.genAttrs nixCiRepositories (repo: {
      enable = true;
      name = "${repo}-ci-1";
      replace = true;
      url = "https://github.com/ttizze/${repo}";
      tokenFile = "/var/lib/${repo}-ci-registration-token";
      tokenType = "registration";
      user = repo;
      group = repo;
      workDir = "/var/lib/${repo}-ci-work";
      extraLabels = [ "nix-ci" ];
      extraPackages = with pkgs; [
        curl
        gh
        jq
        openssh
        unzip
      ];
      extraEnvironment = {
        NIX_REMOTE = "daemon";
        FORCE_JAVASCRIPT_ACTIONS_TO_NODE24 = "true";
      };
      serviceOverrides = {
        PrivateUsers = false;
        Restart = lib.mkForce "always";
        RestartSec = 5;
      };
    })
    // {
      tsurumi = {
        enable = true;
        name = "tsurumi-ci-1";
        replace = true;
        url = "https://github.com/ttizze/cinema-maker";
        tokenFile = "/var/lib/tsurumi-ci-registration-token";
        tokenType = "registration";
        user = "runner";
        group = "runner";
        workDir = "/var/lib/tsurumi-ci-work";
        extraLabels = [ "tsurumi-ci" ];
        extraPackages = with pkgs; [
          bash
          coreutils
          curl
          docker
          gh
          jq
          nodejs_24
          gnumake
          gcc
          gnused
          gnugrep
          findutils
          unzip
          zip
          util-linux
          procps
          cacert
          glibc.bin
        ];
        extraEnvironment = {
          NIX_LD = "${pkgs.stdenv.cc.bintools.dynamicLinker}";
          NIX_LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibraries;
          LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibraries;
          FORCE_JAVASCRIPT_ACTIONS_TO_NODE24 = "true";
          # Helsinkiから遠隔DBへの接続はNodeの既定250msを超える。
          NODE_OPTIONS = "--network-family-autoselection-attempt-timeout=2000";
        };
        serviceOverrides = {
          PrivateUsers = false;
          RestrictNamespaces = false;
          SupplementaryGroups = [ "docker" ];
          # Chromiumの子プロセスが使うcapsetだけを既定の禁止一覧から除く。
          SystemCallFilter = [ "capset" ];
          Restart = lib.mkForce "always";
          RestartSec = 5;
        };
      };
    };
  systemd.services =
    lib.genAttrs (map (repo: "github-runner-${repo}") nixCiRepositories) (service: {
      unitConfig.ConditionPathExists =
        config.services.github-runners.${lib.removePrefix "github-runner-" service}.tokenFile;
    })
    // {
      github-runner-tsurumi = {
        after = [ "docker.service" ];
        unitConfig.ConditionPathExists = config.services.github-runners.tsurumi.tokenFile;
      };
    };
}
