# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, lib, ... }:

{
  imports = [
    ./disko.nix
    ./hardware-configuration.nix

    ../../../modules/roles/nixos/linux-universal.nix
    ../../../modules/roles/nixos/nvidia.nix
    ../../../modules/roles/nixos/server/smb.nix
    ../../../modules/roles/nixos/server/nvidia.nix
    ../../../modules/shared-machine-configs/homelab-node.nix
  ];

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking.hostId = "8425e349";

  hardware.nvidia-container-toolkit.enable = true;

  hardware.nvidia = {
    gsp.enable = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
    open = lib.mkForce false;
  };

  services.rke2 = {
    extraFlags = [
      "--default-runtime=nvidia"
      "--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
    ];
  };

  virtualisation.containerd = {
    enable = true;
    settings = {
      plugins = {
        "io.containerd.grpc.v1.cri" = {
          enable_cdi = true;
          cdi_spec_dirs = ["/etc/cdi" "/var/run/cdi"];
          containerd = {
            default_runtime_name = "nvidia";
            runtimes = {
              nvidia = {
                snapshotter = "overlayfs";
                privileged_without_host_devices = false;
                runtime_type = "io.containerd.runc.v2";
                options = {
                  BinaryName = "${pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime";
                };
              };
            };
          };
        };
      };
    };
  };
}
