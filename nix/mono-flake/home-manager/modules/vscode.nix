{ inputs, globals, pkgs, ...}:

let
  vscode-settings = ../config-files/vscode-settings.json;

  # Unfortunately, some VSCode extensions(!) do not work on aarch64-linux, so let's read what platform we're on,
  # and only apply those if its safe
  platform-specific-extensions = if pkgs.system != "aarch64-linux" then [ms-python.vscode-pylance ms-python.python ms-python.debugpy] else [];
in

{
  programs.vscode = {
    enable = true;

    userSettings = builtins.fromJSON (builtins.readFile vscode-settings);

    mutableExtensionsDir = false;
    extensions = with pkgs.vscode-marketplace; [
      # These guys need to have the full title because of string stuff
      pkgs.vscode-marketplace."4ops".terraform

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
      mechatroner.rainbow-csv
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-ssh-edit
      ms-vscode.remote-explorer
      charliermarsh.ruff
      timonwong.shellcheck
      gruntfuggly.todo-tree
      redhat.vscode-yaml
      slevesque.vscode-zipexplorer
      ms-vscode.powershell
     ];
  };
}