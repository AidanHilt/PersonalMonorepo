# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, lib, ... }:

let
  macHome = "/mnt/shared/aidan";
  user = "aidan";
  homeDir = "/home/${user}";

  # Directories that get pulled in even though they start with a dot.
  extraDotDirs = [ ".ssh" ".kube" ];
in

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix

    ../../../modules/roles/nixos/linux-universal.nix

    ../../../modules/roles/universal/development-machine.nix
    ../../../modules/roles/universal/personal-development.nix

    ../../../modules/roles/nixos/vscode-server.nix
  ];

  environment.systemPackages = with pkgs; [
    ghostty.terminfo
  ];

  security.sudo.wheelNeedsPassword = false;

  # virtualisation.rosetta = {
  #   enable = true;
  #   mountTag = "vz-rosetta";
  # };

  fileSystems."/mnt/shared" = {
    device = "share";
    fsType = "virtiofs";
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  systemd.services.mac-home-binds = {
    description = "Bind-mount Mac home subdirectories into ${homeDir}";
    after = [ "mnt-shared-aidan.mount" ];
    requires = [ "mnt-shared-aidan.mount" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      mount_one() {
        local name="$1"
        local src="${macHome}/$name"
        local dst="${homeDir}/$name"

        [ -d "$src" ] || return 0

        install -d -m 0755 -o ${user} -g users "$dst"
        if ! mountpoint -q "$dst"; then
          mount --bind "$src" "$dst"
        fi
      }

      # Top-level non-dotfile directories, discovered dynamically.
      for dir in ${macHome}/*/; do
        name=$(basename "$dir")
        case "$name" in
          .*) continue ;;
        esac
        mount_one "$name"
      done

      # Explicit dotfile directories.
      for name in ${lib.concatStringsSep " " extraDotDirs}; do
        mount_one "$name"
      done
    '';

    preStop = ''
      for dir in ${homeDir}/*/ ${lib.concatStringsSep " " (map (d: "${homeDir}/${d}") extraDotDirs)}; do
        dir="''${dir%/}"
        mountpoint -q "$dir" 2>/dev/null && umount "$dir" || true
      done
    '';
  };
}

