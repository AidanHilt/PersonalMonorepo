{ config, pkgs, ... }:

let
  p10k-config = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/AidanHilt/PersonalMonorepo/feat/nixos/nix/home-manager/config-files/.p10k.zsh";
  };
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    loginShellInit = p10k-config;

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