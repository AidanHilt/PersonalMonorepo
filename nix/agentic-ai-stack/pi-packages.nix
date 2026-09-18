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

  mkPiPackage = dir:
    let
      workspace = workspaceNameOf dir;
    in
    pkgs.stdenv.mkDerivation (finalAttrs: {
      pname = "pi-packages-${dir}";
      inherit version src;

      pnpmDeps = pkgs.fetchPnpmDeps {
        fetcherVersion = 4;
        inherit (finalAttrs) pname version src;
        hash = hashes.pnpmDeps or pkgs.lib.fakeHash;
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

        cp -R "packages/${dir}/." "$out/"

        rm -rf "$out/node_modules"

        cp -RL "packages/${dir}/node_modules" "$out/node_modules"

        runHook postInstall
      '';

      meta = with lib; {
        description = "${workspace} -- a Pi agentic CLI extension from gotgenes/pi-packages";
        homepage = "https://github.com/gotgenes/pi-packages/tree/main/packages/${dir}";
        license = licenses.mit;
      };
    });

in

lib.genAttrs packageDirs mkPiPackage