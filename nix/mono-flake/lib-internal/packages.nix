{ nixpkgs, darwin, inputs }:

let
  lib = nixpkgs.lib;

  discovery = import ./discovery.nix { inherit nixpkgs darwin inputs; };

  pkgs = import inputs.nixpkgs;
in

{
  # Generate packages for all systems with overlays
  genPkgsFor = systems: overlays: platformOverlays:
    lib.genAttrs (import systems) (system:
      let
        systemOverlays = platformOverlays.${system} or [];
        patches = [
          # (final: prev: {
          #   grub2 = prev.grub2.overrideAttrs (oldAttrs: {
          #     patches = map (patch:
          #       if patch.name or "" == "23_prerequisite_1_key_protector_add_key_protectors_framework.patch"
          #         then patch // { hash = "sha256-5aFHzc5qXBNLEc6yzI17AH6J7EYogcXdLxk//1QgumY="; }
          #       else if patch.name or "" == "23_CVE-2024-49504.patch"
          #         then patch // { hash = "sha256-GejDL9IKbmbSUmp8F1NuvBcFAp2/W04jxmOatI5dKn8="; }
          #       else patch
          #     ) oldAttrs.patches;
          #   });
          # })
          (final: prev: {
            python3 = prev.python3.override {
              packageOverrides = pyFinal: pyPrev: {
                aiohttp = pyPrev.aiohttp.overrideAttrs (_old: rec {
                  version = "3.11.11";
                  src = final.fetchFromGitHub {
                    owner = "aio-libs";
                    repo = "aiohttp";
                    tag = "v${version}";
                    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
                  };
                });
              };
            };
            # Propagate to python3Packages as well
            python3Packages = final.python3.pkgs;
          })
        ];
      in
      import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        config.nvidia.acceptLicense = true;
        overlays = overlays ++ systemOverlays ++ patches;
      }
    );
}