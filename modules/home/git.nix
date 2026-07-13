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
        credential."https://github.com".helper = "!gh auth git-credential";
        credential."https://gist.github.com".helper = "!gh auth git-credential";
      };
    };

    gh = {
      enable = true;
      gitCredentialHelper.enable = true;
      settings.git_protocol = "https";
    };
  };
}
