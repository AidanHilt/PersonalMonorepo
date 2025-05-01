{ inputs, globals, pkgs, ...}:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "powerlevel10k-config";
        src = globals.nixConfig;
        file = "home-manager/config-files/.p10k.zsh";
      }
    ];

    shellAliases = {
      ls = "eza";
      # Let's just leave this, we're doing a fancy ReMarkable setup
      #remouse = "~/Library/Python/3.9/bin/remouse";
    };

    history = {
      size = 10000;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" "copyfile" "copybuffer" "git-auto-fetch" "history" "per-directory-history" "systemadmin" ];
    };

    # initExtra = ''
    #   setopt rmstarsilent
    # '';
  };
}