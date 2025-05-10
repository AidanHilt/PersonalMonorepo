{ inputs, globals, pkgs, ...}:

let
  vscode-settings = ../config-files/vscode-settings.json;

  extensions =
    (import (builtins.fetchGit {
      url = "https://github.com/nix-community/nix-vscode-extensions";
      allRefs = true;
      rev = "5603fb6fb99f68dfc244429c79a7b706ed9a2fd7"; #pragma: allowlist secret
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