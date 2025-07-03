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


}