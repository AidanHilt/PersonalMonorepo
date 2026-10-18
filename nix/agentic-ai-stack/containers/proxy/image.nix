{
  pkgs,
  n2c,
  imageName,
  imageTag,
}:

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
  '';

  # The session-scoped, runtime domain-allowlist service -- see
  # containers/proxy/domain-gate/main.go. Stdlib only (no go.sum), same
  # convention as pkg-broker/main.go and nix/scripts' mkGo.
  domainGate = pkgs.buildGoModule {
    pname = "domain-gate";
    version = "0.1.0";
    src = ./domain-gate;
    proxyVendor = true;
    vendorHash = null;
  };

  # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
  supervise = pkgs.writeShellApplication {
    name = "proxy-entrypoint";
    # domain-gate must be on PATH too -- supervise.sh execs it by name
    # alongside squid, and domain-gate itself execs `squid -k
    # reconfigure`, so both need pkgs.squid here regardless.
    runtimeInputs = [
      pkgs.squid
      pkgs.coreutils
      pkgs.bash
      domainGate
    ];
    text = builtins.readFile ./supervise.sh;
  };

  rootEnv = pkgs.buildEnv {
    name = "proxy-image-root";
    paths = [
      pkgs.squid
      pkgs.coreutils
      pkgs.bash
      pkgs.cacert
      passwdFile
      groupFile
      proxyConfig
      domainGate
      supervise
    ];
    pathsToLink = [
      "/bin"
      "/etc"
    ];
  };

  writableDirs = pkgs.runCommand "squid-writable-dirs" { } ''
    mkdir -p $out/var/spool/squid $out/var/log/squid $out/tmp $out/var/lib/proxy-domains
  '';

  # See containers/pi/image.nix for why this is safe/non-circular and what
  # it's used for.
  contentId = builtins.hashString "sha256" "${rootEnv}-${writableDirs}";

in
{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = [
      rootEnv
      writableDirs
    ];

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
      Entrypoint = [ "/bin/proxy-entrypoint" ];
      Env = [
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
      # No published ports in the image itself — compose.yaml controls
      # what's actually reachable (internal network only, no host
      # publish for the egress proxy port).

      Labels = {
        "sh.pi-sandbox.content-id" = contentId;
      };
    };
  };

  inherit contentId;
}
