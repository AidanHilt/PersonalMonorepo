# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, machine-config, inputs, globals, lib, ... }:

let
  kernel70Pkgs = import inputs.kernel70Nixpkgs { system = pkgs.system; };
in

{
  imports = [
    ./hardware-configuration.nix

    ../../../roles/universal/development-machine.nix
    ../../../roles/universal/personal-development.nix

    ../../../modules/roles/nixos/vscode-server.nix
  ];

  environment.systemPackages = with pkgs; [
    ghostty.terminfo
  ];

  security.sudo.wheelNeedsPassword = false;

  virtualisation.rosetta = lib.mkIf pkgs.stdenv.hostPlatform.isAarch64 {
    enable = true;
    mountTag = "vz-rosetta";
  };

  boot.kernelPackages = kernel70Pkgs.linuxPackages_7_0;

  services.dbus.implementation = "dbus";
}
