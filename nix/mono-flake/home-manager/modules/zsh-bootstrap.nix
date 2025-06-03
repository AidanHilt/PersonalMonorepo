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
        src = pkgs.lib.cleanSource ../config-files;
        file = ".p10k.bootstrap.zsh";
      }
    ];

    history = {
      size = 10000;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" "systemadmin" ];
    };
  };
}