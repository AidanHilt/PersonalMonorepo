# Overlay: pkgs.nono >= 0.81.0, built from source.
#
# Context: nix/agentic-ai-stack-nono/PLAN.md, section 2, "nono source".
# Both nixpkgs and nixpkgs-unstable lag badly behind nolabs-ai/nono's
# releases (0.61.1 in nixpkgs vs. the >= 0.81.0 this stack needs), and
# upstream's own flake `#prebuilt` output for v0.81.0 was found to ship a
# stale/wrong hash for x86_64-linux during this project's spikes -- so we
# do not consume that flake output directly. Instead this overlay builds
# nono from source with `rustPlatform.buildRustPackage`, pinned to the
# `v0.81.0` git tag of https://github.com/nolabs-ai/nono.
#
# IMPORTANT: `src.hash` and `cargoHash` below MUST be re-verified on every
# version bump of this overlay. They are not derivable from anything else
# in this repo -- bump the `version`/`rev` below, replace both hashes with
# `lib.fakeHash`, run a build, and copy the "got: sha256-..." hash Nix
# reports for each in turn (src first, then cargo deps) back into this
# file. Do not reuse hashes across version bumps.
final: prev:

{
  nono = prev.rustPlatform.buildRustPackage rec {
    pname = "nono";
    version = "0.81.0";

    src = prev.fetchFromGitHub {
      owner = "nolabs-ai";
      repo = "nono";
      rev = "v${version}";
      # See the file-level comment above: re-verify on every version bump.
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    # See the file-level comment above: re-verify on every version bump.
    cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

    meta = with prev.lib; {
      description = "Landlock/Seatbelt-based process sandbox (nolabs-ai/nono)";
      homepage = "https://github.com/nolabs-ai/nono";
      license = licenses.mit; # best-effort guess; re-check against upstream's actual LICENSE file.
      mainProgram = "nono";
      platforms = platforms.unix;
    };
  };
}
