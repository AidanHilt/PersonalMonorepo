{ inputs, globals, pkgs, config, ...}:

{

  imports = [
    inputs.agenix.homeManagerModules.default
  ];

  age.secrets.kubeconfig = {
    file = ../../secrets/kubeconfig.age;
    path = "${config.home.homeDirectory}/.kube/config";
    mode = "600";
    symlink = false;
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