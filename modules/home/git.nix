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
      };
    };

    gh = {
      enable = true;
      gitCredentialHelper.enable = true;
      settings.git_protocol = "https";
    };
  };
}
