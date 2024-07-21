{ config, pkgs, ... }:

# let
#   ;
# in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellInit = builtins.fetchFromGitHub {
      url = "https://github.com/AidanHilt/PersonalMonorepo";
      rev = "feat/nixos";
    } + "nix/home-manager/config-files/.p10k.zsh";


    # initExtra = "

    #  ''
    #   source ~/.config/home-manager/.p10k.zsh
    # '';

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    shellAliases = {
      ll = "ls -l";
      update = "sudo nixos-rebuild switch";
    };

    history = {
      size = 10000;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" "copyfile" "copybuffer" "git-auto-fetch" "history" "per-directory-history" "systemadmin" "kube-ps1" ];
    };
  };
}