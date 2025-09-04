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
        nixpkgs-version = if system == "aarch64-darwin" then inputs.nixpkgs-darwin else inputs.nixpkgs;
        systemOverlays = platformOverlays.${system} or [];
        patches = [
          (final: prev: {
            terragrunt = prev.terragrunt.overrideAttrs (oldAttrs: {
              pname = "terragrunt";
              version = "0.45.17";
              vendorHash = "sha256-l9yGP6+Sc1RiRDbtPWI3X07KnUNm7z8Mfe0F89q5B2Y=";

              src = prev.fetchFromGitHub {
                owner = "gruntwork-io";
                repo = "terragrunt";
                rev = "v0.45.17";
                sha256 = "sha256-mNrRzXj9bcHr8gATa7O4nSxCA6AJeM4TdyMj7GB4QMo=";
              };
            });

            grub2 = prev.grub2.overrideAttrs (oldAttrs: {
              patches = map (patch:
                if patch.name or "" == "23_prerequisite_1_key_protector_add_key_protectors_framework.patch"
                  then patch // { hash = "sha256-5aFHzc5qXBNLEc6yzI17AH6J7EYogcXdLxk//1QgumY="; }
                else if patch.name or "" == "23_CVE-2024-49504.patch"
                  then patch // { hash = "sha256-GejDL9IKbmbSUmp8F1NuvBcFAp2/W04jxmOatI5dKn8="; }
                else patch
              ) oldAttrs.patches;
            });
          })
        ];
      in
      import nixpkgs-version {
        inherit system;
        config.allowUnfree = true;
        overlays = overlays ++ systemOverlays ++ patches;
      }
    );
}