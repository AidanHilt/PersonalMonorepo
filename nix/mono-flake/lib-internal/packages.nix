{
  nixpkgs,
  darwin,
  inputs,
}:

let
  inherit (nixpkgs) lib;

  discovery = import ./discovery.nix { inherit nixpkgs darwin inputs; };

  # Shared pkgs-building logic: every package set in this flake (the main
  # per-system pkgs, and any extra flake input built via genExtraPkgsFor) goes
  # through here, so the config knobs (allowUnfree, nvidia licensing, the lima
  # insecure-package allowances) stay in one place instead of drifting between
  # package sets.
  mkPkgs =
    {
      input,
      system,
      overlays ? [ ],
    }:
    import input {
      inherit system overlays;
      config = {
        allowUnfree = true;
        nvidia.acceptLicense = true;
        permittedInsecurePackages = [
          "lima-full-1.2.2"
          "lima-additional-guestagents-1.2.2"
        ];
      };
    };
in

{
  # Generate the main pkgs for all systems, with overlays
  genPkgsFor =
    systems: overlays: platformOverlays:
    lib.genAttrs (import systems) (
      system:
      let
        nixpkgs-version = if system == "aarch64-darwin" then inputs.nixpkgs-darwin else inputs.nixpkgs;
        systemOverlays = platformOverlays.${system} or [ ];
      in
      mkPkgs {
        input = nixpkgs-version;
        inherit system;
        overlays = overlays ++ systemOverlays;
      }
    );

  # Generate extra, unoverlaid package sets for all systems, one per entry in
  # extraPkgsInputs (flake.nix's single place for declaring new package sets,
  # e.g. `{ unstable = inputs.nixpkgs-unstable; }`). Returns
  # `{ <system>.<name> = pkgs; }`, which builders.nix threads into specialArgs
  # as `pkgs-<name>` so any NixOS/darwin/home-manager module can use it.
  genExtraPkgsFor =
    systems: extraPkgsInputs:
    lib.genAttrs (import systems) (
      system:
      lib.mapAttrs (
        _name: input:
        mkPkgs {
          inherit input system;
          overlays = [ ];
        }
      ) extraPkgsInputs
    );
}
