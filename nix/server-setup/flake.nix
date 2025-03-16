{
  description = "A flake managing server configurations";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    personalMonorepo = {
      url = "github:aidanhilt/PersonalMonorepo/feat/staging-cluster-setup";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, agenix, home-manager, ... }@inputs:
  let
    globals = {
      username = "aidan";
      nixConfig = inputs.personalMonorepo + "/nix";
      k8s-cluster-master = "";
    };
  in
  {
    nixosConfigurations = {
      laptop-vm-cluster-1 = import ./machines/laptop-vm-cluster-1.nix { inherit inputs globals nixpkgs; };
      laptop-vm-cluster-2 = import ./machines/laptop-vm-cluster-2.nix { inherit inputs globals nixpkgs; };
      external-user-1-machine-1 = import ./machines/external-user-1-machine-1.nix { inherit inputs globals nixpkgs; };
      staging-cluster-1 = import ./machines/staging-cluster-1.nix { inherit inputs globals nixpkgs; };

      # How we build our bootstrap iso image
      iso_image_x86 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
          ./modules/common.nix
        ];
      };
    };
  };
}
