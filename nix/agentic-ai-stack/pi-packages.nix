# Discovers every package under gotgenes/pi-packages' packages/ directory
# and builds one isolated, pruned derivation per package -- nothing here
# is a hardcoded package list. See hashes.nix for the one thing that
# genuinely can't be derived from the directory listing: fixed-output
# hashes for the fetches. Run ./update-hashes.sh after cloning, and again
# whenever pi-packages' pnpm-lock.yaml changes or a package is
# added/removed/renamed.

{ pkgs, src }:

let
  lib = pkgs.lib;
  version = "unstable-2026-09-16";
  hashes = import ./hashes.nix;

  pnpm = pkgs.pnpm_11;

  # Every directory under packages/ is a package -- read straight off the
  # fetched src, so adding/removing a package upstream needs no edits
  # here. (This does mean src's hash has to be correct before packages
  # can even be enumerated -- see update-hashes.sh.)
  packageDirs = builtins.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${src}/packages")
  );

  # The npm/workspace name pnpm needs for --filter comes straight out of
  # each package's own package.json too, rather than being guessed from
  # a naming convention.
  workspaceNameOf = dir:
    (builtins.fromJSON (builtins.readFile "${src}/packages/${dir}/package.json")).name;

  mkPiPackage = dir:
    let
      workspace = workspaceNameOf dir;
      hash = hashes.packages.${dir} or lib.fakeHash;
    in
    pkgs.stdenv.mkDerivation (finalAttrs: {
      pname = "pi-packages-${dir}";
      inherit version src;

      # Scopes both fetchDeps (below) and pnpm.configHook's install during
      # the real build to just this package's dependency subtree.
      pnpmWorkspaces = [ workspace ];

      pnpmDeps = pnpm.fetchDeps {
        inherit (finalAttrs) pname version src pnpmWorkspaces;
        inherit hash;
      };

      nativeBuildInputs = [
        pkgs.nodejs_22
        pnpm
        pnpm.configHook
      ];

      # noEmit: true in this repo's tsconfig -- nothing to compile.
      buildPhase = ''
        runHook preBuild
        runHook postBuild
      '';

      # Prune to just this package + its own resolved deps (including any
      # workspace-internal ones) rather than the whole monorepo.
      installPhase = ''
        runHook preInstall
        pnpm --filter="${workspace}" deploy --legacy "$out"
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
