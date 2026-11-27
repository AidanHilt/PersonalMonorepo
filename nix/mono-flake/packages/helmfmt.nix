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
      hash = "4de4d9425f41c5ac3cb79a745609a1e086d087072eafba48e59424091da77ef4";
    };
    x86_64-darwin = {
      asset = "Darwin_x86_64";
      hash = "fb0531e4844695360c9e0979e538f1eaeea9faeb49bb24e39e90590840cade46";
    };
    aarch64-linux = {
      asset = "Linux_arm64";
      hash = "06bf4a4f78fa4028d3ced7772d5d55718d82a63bb10456c9ec59619a5f96b7e4";
    };
    x86_64-linux = {
      asset = "Linux_x86_64";
      hash = "56d1724e08188bfda84f32eaf447a0fba7f67c60b1423691e94a2ab3783d66b3";
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
