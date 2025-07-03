{ inputs, globals, pkgs, machine-config, pkgsFor, ...}:

{
  # How we build our bootstrap iso images
  iso_image_x86 = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
      inputs.home-manager.nixosModules.home-manager
      ./modules/nixos/bootstrap-image.nix
    ];
  };

  iso-image-aarch64 = nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";

    specialArgs = {
      pkgs = pkgsFor.aarch64-linux;
      inherit inputs globals;
    };

    modules = [
      (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
      ./modules/roles/nixos/bootstrap-image.nix

      (
        {pkgs, ...}: {
          isoImage = {
            makeEfiBootable = true;
            makeUsbBootable = true;
            squashfsCompression = "zstd -Xcompression-level 6"; #way faster build time
          };
        }
      )
    ];
  };
}