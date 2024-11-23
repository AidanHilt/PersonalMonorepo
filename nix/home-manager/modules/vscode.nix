{ inputs, globals, pkgs, lib, system, ...}:

let
  vscode-settings = globals.personalConfig + "/home-manager/config-files/vscode-settings.json";

  extensions =
    (import (builtins.fetchGit {
      url = "https://github.com/nix-community/nix-vscode-extensions";
      ref = "refs/heads/master";
      rev = "c43d9089df96cf8aca157762ed0e2ddca9fcd71e"; #pragma: allowlist secret
    })).extensions.${pkgs.system};
in

{
  programs.vscode = {
    enable = true;

    userSettings = builtins.fromJSON (builtins.readFile vscode-settings);

    mutableExtensionsDir = false;
    extensions = with extensions.vscode-marketplace; [
      mads-hartmann.bash-ide-vscode
      ms-azuretools.vscode-docker
      brunnerh.file-properties-viewer
      github.vscode-github-actions
      github.vscode-pull-request-github
      golang.go
      hashicorp.hcl
      ms-python.isort
      wholroyd.jinja
      ms-kubernetes-tools.vscode-kubernetes-tools
      ms-vsliveshare.vsliveshare
      shd101wyy.markdown-preview-enhanced
      bbenoist.nix
      ms-python.vscode-pylance
      ms-python.python
      ms-python.debugpy
      mechatroner.rainbow-csv
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-ssh-edit
      ms-vscode.remote-explorer
      charliermarsh.ruff
      timonwong.shellcheck
      extensions.vscode-marketplace."4ops".terraform
      gruntfuggly.todo-tree
      redhat.vscode-yaml
      slevesque.vscode-zipexplorer
      ms-vscode.powershell
     ];
  };
}