{ nixpkgs, darwin, inputs }:

let
  discovery = import ./discovery.nix { inherit nixpkgs darwin inputs; };
in

{
  # Generate packages for all systems with overlays
  genPkgsFor = systems: overlays: platformOverlays:
    lib.genAttrs (import systems) (system:
      let
        nixpkgs-version = if system == "aarch64-darwin" then inputs.nixpkgs-darwin else inputs.nixpkgs;
        systemOverlays = platformOverlays.${system} or [];
      in
      import nixpkgs-version {
        inherit system;
        config.allowUnfree = true;
        overlays = overlays ++ systemOverlays;
      }
    );
}