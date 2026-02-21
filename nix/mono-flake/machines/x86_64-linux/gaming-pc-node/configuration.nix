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

  environment.systemPackages = [ pkgs.nvidia-container-toolkit pkgs.libnvidia-container ];

  networking.hostId = "8425e349";

  hardware = {
    nvidia-container-toolkit = {
      enable = true;
      mount-nvidia-executables = true;
      discovery-mode = "nvml";
    };

    nvidia = {
      gsp.enable = false;
      package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
      open = lib.mkForce false;
    };
  };

  # services.rke2 = {
  #   extraFlags = [
  #     "--default-runtime=nvidia"
  #     "--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
  #   ];
  # };

  systemd.tmpfiles.rules = [
    "L+ /usr/lib - - - - ${config.boot.kernelPackages.nvidiaPackages.legacy_470}/lib"
  ];

  # virtualisation.containerd = {
  #   enable = true;
  #   settings = {
  #     plugins = {
  #       "io.containerd.grpc.v1.cri" = {
  #         cni = lib.mkForce {
  #           bin_dirs = ["/opt/cni/bin" "${pkgs.cni-plugins}/bin"];
  #           conf_dir = "/etc/cni/net.d";
  #         };
  #         enable_cdi = true;
  #         cdi_spec_dirs = ["/etc/cdi" "/var/run/cdi"];
  #         containerd = {
  #           default_runtime_name = "nvidia";
  #           snapshotter = "overlayfs";
  #           runtimes = {
  #             nvidia = {
  #               privileged_without_host_devices = false;
  #               runtime_type = "io.containerd.runc.v2";
  #               options = {
  #                 BinaryName = lib.mkForce "${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime";
  #               };
  #             };
  #           };
  #         };
  #       };
  #     };
  #   };
  # };
}
