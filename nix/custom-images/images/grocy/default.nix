{ pkgs, tag, ... }:
let
  runit = import ../../lib/s6.nix { inherit pkgs tag; };

  phpfpmConfigFile = pkgs.writeText "phpfpm-grocy.conf" ''
    [grocy]
    user = grocy
    group = nginx
    listen = /run/phpfpm/grocy.sock
    listen.owner = nginx
    listen.group = nginx
    pm = dynamic
    pm.max_children = 5
    pm.start_servers = 2
    pm.min_spare_servers = 1
    pm.max_spare_servers = 3
  '';

  nginxConfigFile = pkgs.writeText "nginx-grocy.conf" ''
    events {}
    http {
      include ${pkgs.nginx}/conf/mime.types;
      server {
        listen 80;
        root ${pkgs.grocy}/public;

        location / {
          rewrite ^ /index.php;
        }

        location ~ \.php$ {
          fastcgi_split_path_info ^(.+\.php)(/.+)$;
          fastcgi_pass unix:/run/phpfpm/grocy.sock;
          include ${pkgs.nginx}/conf/fastcgi.conf;
          include ${pkgs.nginx}/conf/fastcgi_params;
        }

        location ~ \.(js|css|ttf|woff2?|png|jpe?g|svg)$ {
          add_header Cache-Control "public, max-age=15778463";
          add_header X-Content-Type-Options nosniff;
          add_header X-Robots-Tag none;
          add_header X-Download-Options noopen;
          add_header X-Permitted-Cross-Domain-Policies none;
          add_header Referrer-Policy no-referrer;
          access_log off;
        }

        try_files $uri /index.php;
      }
    }
  '';

  phpfpmService = runit.mkService {
    name = "phpfpm-grocy";
    run = ''
      export GROCY_CONFIG_FILE=/etc/grocy/config.php
      export GROCY_DB_FILE=/var/lib/grocy/grocy.db
      export GROCY_STORAGE_DIR=/var/lib/grocy/storage
      export GROCY_PLUGIN_DIR=/var/lib/grocy/plugins
      export GROCY_CACHE_DIR=/var/lib/grocy/viewcache

      exec ${pkgs.php82}/bin/php-fpm \
          -F \
          -y ${phpfpmConfigFile} \
          2>&1
    '';
    log = true;
  };

  nginxService = runit.mkService {
    name = "nginx";
    run = ''
      mkdir -p \
        /var/lib/grocy/viewcache \
        /var/lib/grocy/plugins \
        /var/lib/grocy/settingoverrides \
        /var/lib/grocy/storage

      chown -R grocy:nginx /var/lib/grocy

      exec ${pkgs.nginx}/bin/nginx \
        -c ${nginxConfigFile} \
        -g "daemon off;" \
        2>&1
    '';
    finish = ''
      ${pkgs.nginx}/bin/nginx -c ${nginxConfigFile} -s quit
    '';
    log = true;
  };

  rootfs = pkgs.runCommand "rootfs" {} ''
    # Create runtime dirs
    mkdir -p $out/run/phpfpm
    mkdir -p $out/var/log/phpfpm-grocy
    mkdir -p $out/var/log/nginx
    mkdir -p $out/var/lib/grocy

    # Set up runit service dirs
    mkdir -p $out/etc/service
    mkdir -p $out/etc/service/phpfpm-grocy
    mkdir -p $out/etc/service/nginx
  '';

  entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
    mkdir -p /run/service
    cp -r /etc/sv/phpfpm-grocy /run/service/
    cp -r /etc/sv/nginx /run/service/
    chmod -R +w /run/service
    exec ${pkgs.s6}/bin/s6-svscan /run/service
  '';
in
{
  contents = with pkgs; [
    # Runtime deps
    php82
    nginx
    s6
    s6-portable-utils
    grocy
    fakeNss
    uutils-coreutils-noprefix

    # Service definitions
    phpfpmService
    nginxService

    # Root filesystem
    rootfs
  ];

  #enableFakechroot = true;

  # fakeRootCommands = ''
  #   mkdir -p $out/etc/service
  #   mkdir -p $out/etc/service/phpfpm-grocy
  #   mkdir -p $out/etc/service/nginx

  #   ln -s /etc/sv/phpfpm-grocy /etc/service/phpfpm-grocy
  #   ln -s /etc/sv/nginx /etc/service/nginx
  # '';

  config = {
    Entrypoint = ["${entrypoint}"];

    ExposedPorts = { "80/tcp" = {}; };
  };
}