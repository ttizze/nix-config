{
  programs = {
    git = {
      enable = true;
      settings = {
        user = {
          name = "tomolld";
          email = "tomoki2757@gmail.com";
        };
        init.defaultBranch = "main";
        fetch.prune = true;
        alias.clean-gone = ''
          !git fetch --prune && git for-each-ref --format "%(refname:short) %(upstream:track)" refs/heads | awk '$2 == "[gone]" {print $1}' | xargs -r git branch -D
        '';
      };
    };

    gh = {
      enable = true;
      gitCredentialHelper.enable = true;
      settings.git_protocol = "https";
    };
  };
}
