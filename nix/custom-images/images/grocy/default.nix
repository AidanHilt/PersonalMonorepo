{ pkgs, tag }:
let
  # rootfs = pkgs.runCommand "rootfs" {} ''
  #   mkdir -p $out/etc/nginx/conf.d
  # '';
in
{
  contents = pkgs.buildEnv {
    name = "image-root";
    paths = with pkgs; [
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

  config = {
    Cmd = [ "${pkgs.nginx}/bin/nginx" "-c" "/etc/nginx/nginx.conf" ];
    ExposedPorts = {
      "80/tcp" = {};
    };
    WorkingDir = "/";
  };
}