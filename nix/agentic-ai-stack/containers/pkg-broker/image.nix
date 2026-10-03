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

  # Wrapper that prepares the broker's store (chroot store on the shared
  # volume) and then execs the server. See entrypoint.sh. patchShebangs
  # rewrites `#!/usr/bin/env bash` to a store path; this image has no
  # /usr/bin/env.
  entrypointScript = pkgs.runCommand "pkg-broker-entrypoint" { } ''
    mkdir -p $out/bin
    cp ${./entrypoint.sh} $out/bin/pkg-broker-entrypoint
    chmod 0555 $out/bin/pkg-broker-entrypoint
    patchShebangs $out/bin/pkg-broker-entrypoint
  '';

  # The exact, pinned nixpkgs source tree this flake's `pkgs` was
  # instantiated from (see flake.nix's `nixpkgs` input). entrypoint.sh
  # copies it to a plain path at first start, because evaluating a
  # store-path source through a chroot store can fail ("path is not valid").
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
      entrypointScript
    ];
    pathsToLink = [ "/bin" "/etc" ];
  };

  # Writable directories (compose.yaml):
  #   - /srv/shared-nix          the nix-store volume mount point. Used as a
  #                              Nix *chroot store* root (NIX_REMOTE=local?root=...),
  #                              so builds land in /srv/shared-nix/nix/store while
  #                              the broker's own closure stays in the image's
  #                              /nix/store and is never copied to the volume.
  #   - /srv/pkg-broker/bin      the pkg-bin volume: resolved bin/* symlinks,
  #                              mounted read-only into `pi`.
  #   - /srv/pkg-broker/nixpkgs  plain-path copy of the pinned nixpkgs
  #                              (container layer only, NOT shared with pi).
  # Mode 0755 (not 0700) because `pi` reads the shared volumes as a different
  # uid (10001).
  writableDirs = pkgs.runCommand "pkg-broker-writable-dirs" { } ''
    mkdir -p $out/srv/shared-nix $out/srv/pkg-broker/bin $out/srv/pkg-broker/nixpkgs $out/tmp
  '';

  contentId = builtins.hashString "sha256" "${rootEnv}-${nixpkgsConfig}-${writableDirs}-${entrypointScript}";

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
      Entrypoint = [ "/bin/pkg-broker-entrypoint" ];
      Env = [
        "HOME=/var/empty"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_CONF_DIR=/etc/nix"
        "PKG_BROKER_NIXPKGS_PATH=/etc/pkg-broker/nixpkgs"
        "PKG_BROKER_BIN_DIR=/srv/pkg-broker/bin"
        "PKG_BROKER_LISTEN=:8080"
        # Read by entrypoint.sh.
        "PKG_BROKER_SERVER=/bin/pkg-broker"
        "PKG_BROKER_STORE_ROOT=/srv/shared-nix"
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
