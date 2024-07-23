{ config, pkgs, ... }:

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
        src = builtins.fetchGit {
          url = "https://github.com/AidanHilt/PersonalMonorepo.git";
          ref = "feat/nixos";
        };
        file = "nix/home-manager/config-files/.p10k.zsh";
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