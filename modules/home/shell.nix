{ pkgs, ... }:
{
  home.file.".p10k.zsh".source = ../../files/p10k.zsh;

  programs.zsh = {
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
      br = "bun run";
      brd = "bun run dev";
      gc = "git commit";
      ls = "eza --icons=auto";
      ll = "eza -lah --icons=auto --git";
      tree = "eza --tree --icons=auto";
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };

    initContent = ''
      [[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

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
    '';
  };
}
