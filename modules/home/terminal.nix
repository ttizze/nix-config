{
  programs = {
    bat.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    tmux.enable = true;

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };
  };
}
