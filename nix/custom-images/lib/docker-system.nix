{ pkgs, tag, inputs, ... }:

let 
  nix2container = inputs.nix2container.packages.${pkgs.system}.nix2container;

  alpineBasex86 = pkgs.fetchurl {
    url    = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-minirootfs-3.23.0-x86_64.tar.gz";
    sha256 = "";
  };

  alpineDockerx86 = pkgs.dockerTools.importImage {
    name   = "alpine-x86";
    stream = alpineBasex86;
  };

  alpineBaseAarch64 = pkgs.fetchurl {
    url    = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/aarch64/alpine-minirootfs-3.23.0-aarch64.tar.gz";
    sha256 = "";
  };

  alpineDockerAarch64 = pkgs.dockerTools.importImage {
    name   = "alpine-aarch64";
    stream = alpineBaseAarch64;
  };


  baseImageForSystem = system:
    if system == "aarch64-linux" then alpineBaseAarch64
    else if system == "x86_64-linux" then alpineBasex86
    else throw "Unsupported system: ${system}";

in

{ system, alpinePackages, nixPackages }:

let
  baseImage = baseImageForSystem system;

  # Layer 1: Alpine packages installed via apk
  alpineLayer = nix2container.buildLayer {
    deps = [];
    contents = pkgs.runCommand "alpine-pkgs" {} ''
      mkdir -p $out
      apk add --root $out --no-cache --initdb --repositories-file /etc/apk/repositories \
        ${lib.escapeShellArgs alpinePackages}
    '';
  };

  # Layer 2: Nix packages symlinked via buildEnv
  nixEnv = pkgs.buildEnv {
    name = "nix-packages";
    paths = nixPackages;
    pathsToLink = [ "/bin" "/lib" "/share" "/etc" ];
  };

  nixLayer = nix2container.buildLayer {
    deps = nixPackages;
    contents = [ nixEnv ];
  };

in

nix2container.buildImage {
  name = "my-image";
  tag  = "latest";

  fromImage = baseImage;

  layers = [ alpineLayer nixLayer ];

  config = {
    Env = [
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ];
  };
}