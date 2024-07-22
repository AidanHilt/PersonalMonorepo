{ config, pkgs, ... }:

let
  p10k-config = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/AidanHilt/PersonalMonorepo/feat/nixos/nix/home-manager/config-files/.p10k.zsh";
    sha256 = "1nlcca3m0fqfyp7glpfiiw22g4434lvph55j4k6qid0xbjhm9ygk";
  };
in
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
        #Useless comment
        name = "powerlevel10k-config";
        src = p10k-config;
        file = ".p10k.zsh";
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