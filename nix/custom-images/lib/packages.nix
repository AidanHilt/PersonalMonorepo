{ nixpkgs, inputs }:

let 

lib = nixpkgs.lib;

pkgs = import inputs.nixpkgs;

in

{
  genMuslPkgs = system:
    let 
      patches = [
        (final: prev: {
          spdlog = prev.spdlog.overrideAttrs (old: {
            patches = (prev.patches or []) ++ [ ../patches/spdlog-musl.patch ];
            });
          })
        ];

        basePkgs = import nixpkgs {
          inherit system;
          overlays = patches;
        };
      in

      basePkgs.pkgsMusl;
}