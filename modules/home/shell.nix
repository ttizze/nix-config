{
  programs = {
    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        add_newline = false;
        command_timeout = 1000;
        directory.truncation_length = 4;
      };
    };

    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = {
        path = "$HOME/.zsh_history";
        size = 10000;
        save = 10000;
        ignoreDups = true;
        share = true;
      };

      shellAliases = {
        gc = "git commit";
        ls = "eza --icons=auto";
        ll = "eza -lah --icons=auto --git";
        tree = "eza --tree --icons=auto";
      };

      initContent = ''
        repo() {
          local destination
          destination="$(ghq root)/github.com/$1"
          [[ -d "$destination" ]] && cd "$destination"
        }

        fkill() {
          local pid
          pid="$(ps -ef | sed 1d | fzf -m | awk '{print $2}')"
          [[ -n "$pid" ]] && echo "$pid" | xargs kill -9
        }

        gq() {
          local branch
          git branch --merged | sed -e '/^[*]/d' -e '/main/d' -e '/master/d' | while IFS= read -r branch; do
            [[ -n "$branch" ]] && git branch -d "$branch"
          done
        }

        gpm() {
          git pull --prune origin main
        }

        chpwd() {
          eza --icons=auto
        }
      '';
    };
  };
}
