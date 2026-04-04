{ pkgs, tag, ... }:
let
  lib = pkgs.lib;

  # Unpack a single .apk into a store path.
  # Alpine .apks are: gzip(signature) ++ gzip(control.tar) ++ gzip(data.tar)
  # We only want the data tarball.
  unpackApk = apk:
    pkgs.runCommandNoCC "apk-unpacked-${apk.name}" {
      nativeBuildInputs = [ pkgs.python3 ];
    } ''
      mkdir -p $out
      python3 - <<'EOF'
      import gzip, io, sys, tarfile, pathlib

      def iter_gzip_streams(path):
          """Yield each independent gzip stream in a concatenated file."""
          with open(path, "rb") as f:
              data = f.read()
          pos = 0
          while pos < len(data):
              # gzip magic bytes
              if data[pos:pos+2] != b'\x1f\x8b':
                  break
              buf = io.BytesIO(data[pos:])
              with gzip.GzipFile(fileobj=buf) as gz:
                  content = gz.read()
              yield content
              pos += buf.tell()

      streams = list(iter_gzip_streams("${apk}"))
      # stream[0] = signature, stream[1] = control.tar, stream[2] = data.tar
      if len(streams) < 3:
          sys.exit("Expected 3 gzip streams in apk, got " + str(len(streams)))

      data_tar = io.BytesIO(streams[2])
      with tarfile.open(fileobj=data_tar) as t:
          t.extractall("$out")
      EOF
    '';

  # Merge several unpacked apks into one layer derivation
  mkAlpineLayer =
    { packages
    , name       ? "alpine-layer"
    , alpineVersion ? "3.19"
    , arch          ? "x86_64"
    , repo          ? "main"
    }:
    let
      fetchPkg = { name, version, sha256
                 , repo          ? repo
                 , arch          ? arch
                 , alpineVersion ? alpineVersion
                 , ... }:
        pkgs.fetchurl {
          url    = "https://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/${repo}/${arch}/${name}-${version}.apk";
          inherit sha256;
        };

      unpacked = map (p: unpackApk (fetchPkg p)) packages;
    in
    pkgs.symlinkJoin {
      inherit name;
      paths = unpacked;
    };

in

{
  inherit mkAlpineLayer unpackApk;
}