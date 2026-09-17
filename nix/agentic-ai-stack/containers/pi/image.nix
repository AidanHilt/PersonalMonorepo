{ pkgs, n2c, imageName, imageTag }:

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

  agentBundle = pkgs.runCommand "pi-agent-bundle" {} ''
    mkdir -p $out/.pi/agent/extensions/pi-permission-system

    cp ${../../config/pi/settings.json} \
      $out/.pi/agent/settings.json

    cp ${../../config/pi/models.json} \
      $out/.pi/agent/models.json

    cp ${../../config/pi/permission-system.config.json} \
      $out/.pi/agent/extensions/pi-permission-system/config.json

    mkdir -p $out/.pi/agent/defaults

    cp ${../../config/pi/AGENTS.md} \
      $out/.pi/agent/defaults/AGENTS.md
  '';

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

    copyToRoot = pkgs.buildEnv {
      name = "pi-image-root";

      paths = [
        piPackages.pi-permission-system
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
    };

    perms = [
      # {
      #   path = piPermissionSystem;
      #   regex = ".*";
      #   mode = "0755";
      #   uid = pkgs.lib.toInt uid;
      #   gid = pkgs.lib.toInt gid;
      # }

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
        "PI_AGENT_DIR=${home}/.pi/agent"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NO_COLOR=0"
      ];
    };
  };
}