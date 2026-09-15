{ pkgs, n2c, imageName, imageTag }:

let
  # ------------------------------------------------------------------
  # Pi CLI + the pi-permission-system extension, pinned via a real
  # npm-generated package-lock.json (npm-src/package-lock.json).
  #
  # Regenerate the lockfile (and re-run `nix build` to refresh
  # npmDepsHash) whenever bumping either version:
  #   cd containers/pi/npm-src && npm install --package-lock-only
  #
  # NOTE for implementer: `npmDepsHash` below is a placeholder. Run the
  # build once, Nix will print the real hash in its mismatch error;
  # paste it in. (Standard buildNpmPackage bootstrap dance — this repo
  # can't compute a Nix FOD hash without a Nix daemon available.)
  # ------------------------------------------------------------------
  piDeps = pkgs.buildNpmPackage {
    pname = "pi-sandbox-image-deps";
    version = "0.0.0";
    src = ./npm-src;
    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    dontNpmBuild = true;
    # We only want node_modules out of this; nothing to install globally.
    installPhase = ''
      mkdir -p $out
      cp -r node_modules $out/node_modules
      cp package.json package-lock.json $out/
    '';
  };

  user = "pi";
  uid = "10001";
  gid = "10001";
  home = "/home/${user}";

  passwdFile = pkgs.writeTextFile {
    name = "passwd";
    destination = "/etc/passwd";
    text = ''
      root:x:0:0:root:/root:/bin/sh
      ${user}:x:${uid}:${gid}:pi sandbox user:${home}:/bin/sh
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

  # ~/.pi/agent bundle baked into the image: AGENTS.md, settings.json,
  # models.json, and the permission-system config. No secrets in here —
  # see config/pi/README.md and spec §5/§7.
  agentBundle = pkgs.runCommand "pi-agent-bundle" { } ''
    mkdir -p $out/.pi/agent/extensions/pi-permission-system
    cp ${../../config/pi/settings.json} $out/.pi/agent/settings.json
    cp ${../../config/pi/models.json} $out/.pi/agent/models.json
    cp ${../../config/pi/permission-system.config.json} \
       $out/.pi/agent/extensions/pi-permission-system/config.json
    # AGENTS.md is loaded from the project directory (the bind-mounted
    # monorepo), not baked in here — see entrypoint.sh, which falls back
    # to this copy only if the mounted project has none of its own.
    mkdir -p $out/.pi/agent/defaults
    cp ${../../config/pi/AGENTS.md} $out/.pi/agent/defaults/AGENTS.md
  '';

  entrypoint = pkgs.writeShellApplication {
    name = "pi-entrypoint";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.git pkgs.coreutils pkgs.bash ];
    text = builtins.readFile ./entrypoint.sh;
  };

in
{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = pkgs.buildEnv {
      name = "pi-image-root";
      paths = [
        pkgs.nodejs_22
        pkgs.git
        pkgs.coreutils
        pkgs.bash
        pkgs.cacert
        pkgs.gnugrep
        pkgs.gnused
        pkgs.findutils
        passwdFile
        groupFile
        entrypoint
      ];
      pathsToLink = [ "/bin" "/etc" ];
    };

    # Node runtime + pinned pi/permission-system packages + the config
    # bundle, laid out under the pi user's home directory.
    perms = [
      {
        path = piDeps;
        regex = ".*";
        mode = "0755";
        uid = pkgs.lib.toInt uid;
        gid = pkgs.lib.toInt gid;
      }
      {
        path = agentBundle;
        regex = ".*";
        mode = "0700";
        uid = pkgs.lib.toInt uid;
        gid = pkgs.lib.toInt gid;
      }
    ];

    config = {
      User = "${uid}:${gid}";
      WorkingDir = "/workspace";
      Entrypoint = [ "/bin/pi-entrypoint" ];
      Env = [
        "HOME=${home}"
        "NODE_PATH=${piDeps}/node_modules"
        "PATH=/bin:${piDeps}/node_modules/.bin"
        "PI_AGENT_DIR=${home}/.pi/agent"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NO_COLOR=0"
      ];
      # Explicitly no EXPOSE'd ports: pi never listens, it only makes
      # outbound calls (to `proxy`).
    };
  };
}
