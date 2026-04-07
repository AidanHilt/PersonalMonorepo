{ pkgs, tag, ... }:
let
  lib = pkgs.lib;

  unpackApk = apk:
    pkgs.runCommand "apk-unpacked-${apk.name}" {
      nativeBuildInputs = [ pkgs.apk-tools ];
    } ''
      mkdir -p $out
      ${pkgs.apk-tools}/bin/apk extract --destination $out ${apk} --allow-untrusted 
    '';

  # Merge several unpacked apks into one layer derivation
  mkAlpineLayer =
    { packages
    , name       ? "alpine-layer"
    , alpineVersion ? "3.23"
    , arch          ? "x86_64"
    , repo          ? "main"
    }:
    let
      defaultAlpineVersion = alpineVersion;
      defaultArch          = arch;
      defaultRepo          = repo;

      fetchPkg = { name, version, sha256
               , repo          ? defaultRepo
               , arch          ? defaultArch
               , alpineVersion ? defaultAlpineVersion
               , ... }:
        pkgs.fetchurl {
          url    = "https://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/${repo}/${arch}/${name}-${version}.apk";
          inherit sha256;
        };

      unpacked = map (p: unpackApk (fetchPkg p)) packages;
    in
    pkgs.symlinkJoin {
      inherit name;
      paths = [unpacked];
    };

in

{
  inherit mkAlpineLayer unpackApk;
}