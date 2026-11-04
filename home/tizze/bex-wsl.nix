# The WSL PC carries only remote-agent's build pair; its interactive shell is unmanaged.
{
  imports = [ ../../modules/home/bex-builder.nix ];

  home = {
    username = "tizze";
    homeDirectory = "/home/tizze";
    stateVersion = "26.05";
  };
}
