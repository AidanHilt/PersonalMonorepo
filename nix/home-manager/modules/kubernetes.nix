 { inputs, globals, pkgs, lib, system, config, ...}:

{

  imports = [
    inputs.agenix.homeManagerModules.default
  ];

  age.secrets.kubeconfig = {
    file = globals.nixConfig + "/secrets/kubeconfig.age";
    path = "${config.home.homeDirectory}/.kube/config";
    mode = "700";
  };

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