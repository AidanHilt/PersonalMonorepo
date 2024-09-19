{ config, pkgs, lib, ...}:

let
  system = builtins.currentSystem;
  extensions =
    (import (builtins.fetchGit {
      url = "https://github.com/nix-community/nix-vscode-extensions";
      ref = "refs/heads/master";
      rev = "c43d9089df96cf8aca157762ed0e2ddca9fcd71e"; #pragma: allowlist secret
    })).extensions.${system};

  vscode-settings = builtins.fetchGit {
    url = "https://github.com/AidanHilt/PersonalMonorepo.git";
    ref = "feat/nix-darwin";
    rev = "da16d2c28fde0d085e4276bccdf9aa1bcd13e37d"; #pragma: allowlist secret
  } + "/nix/home-manager/config-files/vscode-settings.json";
in

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.

  home.stateVersion = "24.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [];

  home.sessionVariables = {};

  home.activation.firefoxProfile = lib.hm.dag.entryAfter [ "writeBoundry" ] ''
    run mv $HOME/Library/Application\ Support/Firefox/profiles.ini $HOME/Library/Application\ Support/Firefox/profiles.hm
    run cp $HOME/Library/Application\ Support/Firefox/profiles.hm $HOME/Library/Application\ Support/Firefox/profiles.ini
    run rm -f $HOME/Library/Application\ Support/Firefox/profiles.ini.bak
    run chmod u+w $HOME/Library/Application\ Support/Firefox/profiles.ini
  '';

  programs.firefox = {
    enable = true;
    package = null;
    profiles.aidan = {
      isDefault = true;
      extensions = with pkgs.nur.repos.rycee.firefox-addons; [
        clearurls
        docsafterdark
        don-t-fuck-with-paste
        facebook-container
        keepassxc-browser
        privacy-badger
        refined-github
        sponsorblock
        ublock-origin
        view-image
      ];


      extraConfig = ''
        user_pref("extensions.autoDisableScopes", 0);
        user_pref("extensions.enabledScopes", 15);
      '';

    };
  };

  programs.vim = {
    enable = true;
    defaultEditor = true;

    extraConfig = ''
      set backspace=indent,eol,start
    '';

    settings = {
      expandtab = true;
      tabstop = 2;
      shiftwidth = 2;

      number = true;
    };
  };

  programs.vscode = {
    enable = true;

    # TODO Get to
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
      vscodevim.vim
      redhat.vscode-yaml
      slevesque.vscode-zipexplorer
     ];
  };

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
        src = builtins.fetchGit {
          url = "https://github.com/AidanHilt/PersonalMonorepo.git";
          ref = "feat/nix-darwin";
          rev = "be2226c0996426cbc76ecc050c84e36071ad6ac3"; #pragma: allowlist secret
        };
        file = "nix/home-manager/config-files/.p10k.zsh";
      }
    ];

    shellAliases = {
      ls = "eza";
      update = "sudo nixos-rebuild switch";
      kctx = "kubectx";
      kns = "kubens";
    };

    history = {
      size = 10000;
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "sudo" "copyfile" "copybuffer" "git-auto-fetch" "history" "per-directory-history" "systemadmin" "kubectl" ];
    };

    initExtra = ''
      setopt rmstarsilent
    '';
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}