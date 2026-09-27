{ config, pkgs, machine-config, inputs, lib, globals, ... }:

{
  imports = [
    (inputs.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
    ../../../modules/shared-machine-configs/bootstrap-image.nix
  ];

  isoImage = {
    makeEfiBootable = true;
    makeUsbBootable = true;
    isoBaseName = lib.mkForce "atils-nixos-bootstrap-x86_64";
    squashfsCompression = "zstd -Xcompression-level 6"; #way faster build time
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs globals pkgs machine-config; };
    users.root = import ./home.nix {inherit inputs globals pkgs machine-config; system = pkgs.system; lib = inputs.home-manager.lib; };
  };
}
