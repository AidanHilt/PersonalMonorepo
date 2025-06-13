{ inputs, globals, pkgs, machine-config, ...}:

let
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
  imports = [
    ./_adguard.nix
    ./_fixed-ip-machine.nix
    ./_keepalived.nix
    ./_rke.nix
  ];

  # services.openssh = {
  #   hostKeys = [
  #     {
  #       path = "/etc/ssh/ssh_host_ed25519_key";
  #       type = "ed25519";
  #     }
  #   ];
  # };

  environment.systemPackages = with pkgs; [
    htop
    update
  ];
}