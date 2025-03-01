{ inputs, globals, pkgs, ...}:

let
  upload-host-key = pkgs.writeShellScriptBin "upload-host-key" ''
    curl -F "file=@/etc/ssh/ssh_host_ed25519_key.pub https://x0.at"
  '';

  update = pkgs.writeShellScriptBin "update" ''
    BRANCH="master"
    while [[ $# -gt 0 ]]; do
      case $1 in
        --branch)
          BRANCH="$2"
          shift 2
          ;;
        *)
          echo "Unknown option: $1"
          exit 1
          ;;
      esac
    done
    sudo nixos-rebuild switch --flake "github:AidanHilt/PersonalMonorepo/$BRANCH?dir=nix/server-setup"
  '';
in

{
  users.groups.aidan = {};

  services.openssh = {
    enable = true;

    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  users.users.aidan = {
    home = "/home/aidan";
    group = "aidan";
    extraGroups = [ "networkmanager" "wheel" ];
    isNormalUser = true;

    openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIImw5CsGmsR1WTunv5bvNcozmoUSgJf76RMvy6SZtA2R aidan@hyperion"];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.eza
    pkgs.htop
    upload-host-key
    update
  ];

  system.stateVersion = "24.11";

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.zsh;
}