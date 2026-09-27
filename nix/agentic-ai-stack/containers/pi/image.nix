{ pkgs, n2c, imageName, imageTag, piPackages }:

let
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

  extensions = [
    piPackages.pi-permission-system
    piPackages.pi-anthropic-auth
  ];

  # Single, self-contained seed of the entire ~/.pi/agent tree. At runtime
  # the entrypoint copies this into the writable ~/.pi tmpfs in one shot;
  # the source of truth stays immutable in the image. Extensions and the
  # permission-system policy are baked into their final locations here, so
  # the entrypoint needs no rm/cp dance or dynamic folder lookup.
  piSeed = pkgs.runCommand "pi-seed" { } (
    ''
      mkdir -p $out/workspace
      mkdir -p $out/home/pi/.pi-seed/agent
      mkdir -p $out/home/pi/.pi

      cp ${../../config/pi/settings.json} \
        $out/home/pi/.pi-seed/agent/settings.json

      cp ${../../config/pi/models.json} \
        $out/home/pi/.pi-seed/agent/models.json

      mkdir -p $out/home/pi/.pi-seed/agent/defaults
      cp ${../../config/pi/AGENTS.md} \
        $out/home/pi/.pi-seed/agent/defaults/AGENTS.md

      mkdir -p $out/home/pi/.pi-seed/agent/extensions
    ''
    + pkgs.lib.concatMapStringsSep "\n" (ext: ''
      mkdir -p "$out/home/pi/.pi-seed/agent/extensions/${ext.name}"
      cp -r --no-preserve=mode ${ext}/. "$out/home/pi/.pi-seed/agent/extensions/${ext.name}/"
    '') extensions
    + ''

      cp ${../../config/pi/permission-system.config.json} \
        "$out/home/pi/.pi-seed/agent/extensions/${piPackages.pi-permission-system.name}/config.json"
    ''
    );

  entrypoint = pkgs.writeShellApplication {
    name = "pi-entrypoint";
    runtimeInputs = [
      pkgs.pi-coding-agent

      pkgs.git
      pkgs.coreutils
      pkgs.bash
    ];
    text = builtins.readFile ./entrypoint.sh;
  };

in

{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = [

      piSeed

      (pkgs.buildEnv {
      name = "pi-image-root";

      paths = [
        pkgs.pi-coding-agent
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

      pathsToLink = [
        "/bin"
        "/etc"
        "/lib"
      ];
      })
    ];

    perms = [
      {
        path = piSeed;
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
        "PI_AGENT_DIR=${home}/.pi/agent"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NO_COLOR=0"
      ];
    };
  };
}