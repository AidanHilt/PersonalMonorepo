{ inputs, globals, pkgs, ...}:

let
  vscode-settings = ../config-files/vscode-settings.json;

  # Unfortunately, some VSCode extensions(!) do not work on aarch64-linux, so let's read what platform we're on,
  # and only apply those if its safe
  platform-specific-extensions = if pkgs.system != "aarch64-linux" then with pkgs.vscode-marketplace;[ms-python.vscode-pylance ms-python.python ms-python.debugpy] else [];
in

{
  programs.vscode.profile.default = {
    enable = true;

    userSettings = builtins.fromJSON (builtins.readFile vscode-settings);

    mutableExtensionsDir = false;
    extensions = with pkgs.vscode-marketplace; [
      # These guys need to have the full title because of string stuff
      pkgs.vscode-marketplace."4ops".terraform

      bbenoist.nix
      brunnerh.file-properties-viewer
      charliermarsh.ruff
      github.vscode-github-actions
      github.vscode-pull-request-github
      golang.go
      gruntfuggly.todo-tree
      hashicorp.hcl
      mads-hartmann.bash-ide-vscode
      mechatroner.rainbow-csv
      ms-azuretools.vscode-docker
      ms-kubernetes-tools.vscode-kubernetes-tools
      ms-python.isort
      ms-vscode-remote.remote-ssh
      ms-vscode-remote.remote-ssh-edit
      ms-vscode.powershell
      ms-vscode.remote-explorer
      ms-vsliveshare.vsliveshare
      redhat.vscode-yaml
      shd101wyy.markdown-preview-enhanced
      slevesque.vscode-zipexplorer
      timonwong.shellcheck
      wholroyd.jinja
     ];
  };
}