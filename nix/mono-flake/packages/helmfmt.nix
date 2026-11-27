# helmfmt is not packaged in nixpkgs, and upstream publishes prebuilt
# release binaries (GoReleaser) alongside each tag. Pin those per-system
# instead of building from source, so this derivation needs no `vendorHash`
# and never has to reach the network at evaluation time. The hashes below are
# upstream's own release checksums; re-fetch them when bumping `version`.
{
  lib,
  stdenv,
  fetchurl,
}:

let
  version = "0.7.0";

  sources = {
    aarch64-darwin = {
      asset = "Darwin_arm64";
      hash = "sha256-TeTZQl9Bxaw8t5p0Vgmh4IbQhwcur7pI5ZQkCR2nfvQ=";
    };
    x86_64-darwin = {
      asset = "Darwin_x86_64";
      hash = "";
    };
    aarch64-linux = {
      asset = "Linux_arm64";
      hash = "";
    };
    x86_64-linux = {
      asset = "Linux_x86_64";
      hash = "";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "helmfmt: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "helmfmt";
  inherit version;

  src = fetchurl {
    url = "https://github.com/digitalstudium/helmfmt/releases/download/v${version}/helmfmt_${source.asset}.tar.gz";
    inherit (source) hash;
  };

  # The release tarballs ship the binary at the archive root, next to LICENSE
  # and README.md, with no `configure`/`make` step to run.
  dontBuild = true;
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 helmfmt "$out/bin/helmfmt"

    runHook postInstall
  '';

  meta = {
    description = "Formatter for Helm chart templates";
    homepage = "https://github.com/digitalstudium/helmfmt";
    license = lib.licenses.gpl3Only;
    mainProgram = "helmfmt";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
