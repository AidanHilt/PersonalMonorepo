{ pkgs, tag }:
let
  rootfs = pkgs.runCommand "rootfs" {} ''
    mkdir -p $out/etc/nginx/conf.d
  '';
in
{
  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = with pkgs; [
      fakeNss
      rootfs

      php85
      php85Extensions.gd
      php85Extensions.intl
      php85Extensions.ldap
      php85Extensions.pdo
      php85Extensions.pdo_sqlite
      php85Extensions.tokenizer

      grocy
    ];
  };

  runAsRoot = ''
    mkdir -p var/log/nginx
    mkdir -p var/cache/nginx
    mkdir -p tmp/client_body tmp/proxy tmp/fastcgi tmp/uwsgi tmp/scgi
    chmod 1777 tmp
  '';

  config = {
    Cmd = [ "${pkgs.nginx}/bin/nginx" "-c" "/etc/nginx/nginx.conf" ];
    ExposedPorts = {
      "80/tcp" = {};
    };
    WorkingDir = "/";
  };
}