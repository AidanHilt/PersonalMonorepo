{ pkgs, n2c, imageName, imageTag }:

let
  user = "pkg-broker";
  uid = "10003";
  gid = "10003";

  passwdFile = pkgs.writeTextFile {
    name = "passwd";
    destination = "/etc/passwd";
    text = ''
      root:x:0:0:root:/root:/bin/sh
      ${user}:x:${uid}:${gid}:pkg-broker sandbox user:/var/empty:/bin/sh
    '';
  };
  groupFile = pkgs.writeTextFile {
    name = "group";
    destination = "/etc/group";
    text = ''
      root:x:0:
      ${user}:x:${gid}:
    '';
  };

  server = pkgs.buildGoModule {
    pname = "pkg-broker";
    version = "0.1.0";
    src = ./.;
    proxyVendor = true;
    # Stdlib only (no go.sum) -- see nix/scripts' mkGo convention for the
    # same pattern (nix/scripts/flake.nix).
    vendorHash = null;
  };

  # The exact, pinned nixpkgs source tree this flake's `pkgs` was
  # instantiated from (same input as everything else in this flake --
  # see flake.nix's `nixpkgs` input). This is what "validate it resolves
  # against the repo's pinned nixpkgs input" (decision 2) means in
  # practice: `nix-build -A <attr> <this path>`, no flake refs, no
  # arbitrary expressions. Baking the actual source tree in (rather than
  # a flake registry entry) means attribute resolution never depends on
  # pkg-broker's external network leg being reachable at eval time --
  # only at fetch/build time, for sources/substitutes themselves.
  nixpkgsConfig = pkgs.runCommand "pkg-broker-nixpkgs-config" { } ''
    mkdir -p $out/etc/nix $out/etc/pkg-broker
    cp ${./nix.conf} $out/etc/nix/nix.conf
    ln -s ${pkgs.path} $out/etc/pkg-broker/nixpkgs
  '';

  rootEnv = pkgs.buildEnv {
    name = "pkg-broker-image-root";
    paths = [
      pkgs.nix
      pkgs.cacert
      pkgs.coreutils
      pkgs.bash
      pkgs.gnutar
      pkgs.gzip
      pkgs.xz
      passwdFile
      groupFile
      server
    ];
    pathsToLink = [ "/bin" "/etc" ];
  };

  # Writable mount points for the two shared volumes (compose.yaml):
  #   - /nix               the nix-store volume (decision 3/4): pkg-broker's
  #                        own store by default, or the host's real
  #                        /nix (store + daemon socket) via
  #                        compose.pkgbroker-host-store.yaml.
  #   - /srv/pkg-broker/bin the pkg-bin volume (decision 4): resolved
  #                        bin/* symlinks, mounted read-only into `pi`.
  # Mode 0755 (not 0700, unlike pi/proxy's placeholders) because `pi`
  # reads these as a *different* uid (10001) -- see PROJECT-SPEC.md.
  writableDirs = pkgs.runCommand "pkg-broker-writable-dirs" { } ''
    mkdir -p $out/nix $out/srv/pkg-broker/bin $out/tmp
  '';

  contentId = builtins.hashString "sha256" "${rootEnv}-${nixpkgsConfig}-${writableDirs}";

in
{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = [ rootEnv nixpkgsConfig ];

    perms = [
      {
        path = writableDirs;
        regex = ".*";
        mode = "0755";
        uid = pkgs.lib.toInt uid;
        gid = pkgs.lib.toInt gid;
      }
    ];

    config = {
      User = "${uid}:${gid}";
      Entrypoint = [ "/bin/pkg-broker" ];
      Env = [
        "HOME=/var/empty"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_CONF_DIR=/etc/nix"
        "PKG_BROKER_NIXPKGS_PATH=/etc/pkg-broker/nixpkgs"
        "PKG_BROKER_BIN_DIR=/srv/pkg-broker/bin"
        "PKG_BROKER_LISTEN=:8080"
      ];
      # No published ports in the image itself -- compose.yaml attaches
      # pkg-broker to `internal` (so `pi` can reach it at
      # http://pkg-broker:8080/resolve) and separately to `external`
      # (its own unproxied leg for cache/source fetches), but never
      # publishes a host port -- same posture as `proxy`.

      Labels = {
        "sh.pi-sandbox.content-id" = contentId;
      };
    };
  };

  inherit contentId;
}
