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
        (final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pyFinal: pyPrev: {
      aiohttp = pyPrev.aiohttp.overridePythonAttrs (old: {
        disabledTests = (old.disabledTests or []) ++ [
          "test_tcp_connector_socket_factory"
          "test_available_connections_with_limit_per_host"
        ];
      });
    })
  ];
})
        ];
      in
      import nixpkgs-version {
        inherit system;
        config.allowUnfree = true;
        config.nvidia.acceptLicense = true;
        config.permittedInsecurePackages = [
          "lima-full-1.2.2"
          "lima-additional-guestagents-1.2.2"
        ];
        overlays = overlays ++ systemOverlays ++ patches;
      }
    );
}