 { inputs, globals, pkgs, lib, system, ...}:

{
  modules = [
    inputs.agenix.homeManagerModules.default {
      age.secrets.kubeconfig = {
        file = globals.nixConfig + "/secrets/kubeconfig.age";
        path = str("${inputs.agenix.homeManagerModules.default.config.home.homeDirectory}/.kube/config");
        mode = "700";
        symlink = false;
      };
    }
  ];

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