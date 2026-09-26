{ pkgs, src }:

let
  lib = pkgs.lib;

  version = "unstable-2026-09-16";
  hashes = import ./hashes.nix;
  pnpm = pkgs.pnpm_11;

  packageDirs = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${src}/packages")
  );

  workspaceNameOf = dir:
    (builtins.fromJSON (builtins.readFile "${src}/packages/${dir}/package.json")).name;

  mkPiPackageFromSrc = { pname, version, src, workspace, pnpmHash, subPath ? ".", homepage ? null }:
    pkgs.stdenv.mkDerivation (finalAttrs: {
      inherit pname version src;

      pnpmDeps = pkgs.fetchPnpmDeps {
        fetcherVersion = 4;
        inherit (finalAttrs) pname version src;
        hash = pnpmHash;
      };

      nativeBuildInputs = [
        pkgs.nodejs_22
        pnpm
        pkgs.pnpmConfigHook
      ];

      buildPhase = ''
        runHook preBuild
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p "$out"

        cp -R "${subPath}/." "$out/"

        rm -rf "$out/node_modules"

        cp -RL "${subPath}/node_modules" "$out/node_modules"

        runHook postInstall
      '';

      meta = with lib;
        {
          description = "${workspace} -- a Pi agentic CLI extension";
          license = licenses.mit;
        }
        // lib.optionalAttrs (homepage != null) { inherit homepage; };
    });

  mkPiPackage = dir:
    let
      workspace = workspaceNameOf dir;
    in
    mkPiPackageFromSrc {
      pname = "pi-packages-${dir}";
      inherit version src;
      pnpmHash = hashes.packages.${dir};
      subPath = "packages/${dir}";
      inherit workspace;
      homepage = "https://github.com/gotgenes/pi-packages/tree/main/packages/${dir}";
    };

in

{
  inherit mkPiPackage mkPiPackageFromSrc;

  pi-packages = lib.genAttrs packageDirs mkPiPackage;
}