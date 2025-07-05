{ nixpkgs, darwin, inputs }:

let
  lib = nixpkgs.lib;

  discovery = import ./discovery.nix { inherit nixpkgs darwin inputs; };
in

{
  # Generate packages for all systems with overlays
  genPkgsFor = systems: overlays: platformOverlays:
    lib.genAttrs (import systems) (system:
      let
        nixpkgs-version = if system == "aarch64-darwin" then inputs.nixpkgs-darwin else inputs.nixpkgs;
        systemOverlays = platformOverlays.${system} or [];
        patches = [
          (final: prev: {
            grub2 = prev.grub2.overrideAttrs (oldAttrs: {
              patches = map (patch: 
                if patch.name or "" == "23_prerequisite_1_key_protector_add_key_protectors_framework.patch"
                then patch // { hash = "sha256-5aFHzc5qXBNLEc6yzI17AH6J7EYogcXdLxk//1QgumY="; }
                else patch
              ) oldAttrs.patches;
            });
          })
        ];
      in
      import nixpkgs-version {
        inherit system;
        config.allowUnfree = true;
        overlays = overlays ++ systemOverlays;
      }
    );
}