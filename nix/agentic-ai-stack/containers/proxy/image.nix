{ pkgs, n2c, imageName, imageTag }:

let
  user = "proxy";
  uid = "10002";
  gid = "10002";

  passwdFile = pkgs.writeTextFile {
    name = "passwd";
    destination = "/etc/passwd";
    text = ''
      root:x:0:0:root:/root:/bin/sh
      ${user}:x:${uid}:${gid}:proxy sandbox user:/var/empty:/bin/sh
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

  proxyConfig = pkgs.runCommand "proxy-config" { } ''
    mkdir -p $out/etc/proxy $out/etc/squid
    cp ${./squid.conf} $out/etc/proxy/squid.conf
    cp ${./allowed-domains.txt} $out/etc/squid/allowed-domains.txt
    cp ${./ollama-gate.nginx.conf.template} $out/etc/proxy/ollama-gate.nginx.conf.template
  '';

  supervise = pkgs.writeShellApplication {
    name = "proxy-entrypoint";
    runtimeInputs = [ pkgs.squid pkgs.nginx pkgs.gettext pkgs.coreutils pkgs.bash ];
    text = builtins.readFile ./supervise.sh;
  };

in
{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = pkgs.buildEnv {
      name = "proxy-image-root";
      paths = [
        pkgs.squid
        pkgs.nginx
        pkgs.gettext # envsubst
        pkgs.coreutils
        pkgs.bash
        pkgs.cacert
        passwdFile
        groupFile
        proxyConfig
        supervise
      ];
      pathsToLink = [ "/bin" "/etc" ];
    };

    perms = [
      {
        path = pkgs.runCommand "squid-writable-dirs" { } ''
          mkdir -p $out/var/spool/squid $out/var/log/squid
        '';
        regex = ".*";
        mode = "0755";
        uid = pkgs.lib.toInt uid;
        gid = pkgs.lib.toInt gid;
      }
    ];

    config = {
      User = "${uid}:${gid}";
      Entrypoint = [ "/bin/proxy-entrypoint" ];
      Env = [
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
      # No published ports in the image itself — compose.yaml controls
      # what's actually reachable (internal network only, no host
      # publish for either the egress proxy port or the Ollama gate).
    };
  };
}
