{ inputs, globals, pkgs, config, ...}:

{
  programs.zsh = {
    enable = true;

    shellAliases = {
      kctx = "kubecm switch";
      kns = "kubecm namespace";
      kctx-add = "kubecm add";
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "kubectl" ];
    };
  };
}