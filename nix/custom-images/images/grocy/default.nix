{ pkgs, tag, ... }:
let
  runit = import ../../lib/s6.nix { inherit pkgs tag; };

  phpfpmConfigFile = pkgs.writeText "phpfpm-grocy.conf" ''
    [grocy]
    clear_env = no
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
    user nginx nginx;
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

      mkdir -p \
        /var/lib/grocy/viewcache \
        /var/lib/grocy/plugins \
        /var/lib/grocy/settingoverrides \
        /var/lib/grocy/storage \
        /tmp

      exec ${pkgs.php82}/bin/php-fpm \
          -F \
          -y ${phpfpmConfigFile} \
          2>&1
    '';
    log = false;
  };

  nginxService = runit.mkService {
    name = "nginx";
    run = ''
      mkdir -p \
        /var/lib/grocy/viewcache \
        /var/lib/grocy/plugins \
        /var/lib/grocy/settingoverrides \
        /var/lib/grocy/storage \
        /var/log/nginx

      chown -R grocy:nginx /var/lib/grocy

      exec ${pkgs.nginx}/bin/nginx \
        -c ${nginxConfigFile} \
        -g "daemon off;" \
        2>&1
    '';
    finish = ''
      ${pkgs.nginx}/bin/nginx -c ${nginxConfigFile} -s quit
    '';
    log = false;
  };


  entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
    mkdir -p /run/service
    mkdir -p /run/phpfpm
    cp -r /etc/sv/phpfpm-grocy /run/service/
    cp -r /etc/sv/nginx /run/service/
    exec ${pkgs.s6}/bin/s6-svscan /run/service
  '';
in
{
  contents = with pkgs; [
    # Runtime deps
    s6
    s6-portable-utils

    # Service definitions
    phpfpmService
    nginxService

    (pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      nobody:x:65534:65534:nobody:/var/empty:/bin/false
      grocy:x:1000:1000::/var/lib/grocy:/bin/false
      nginx:x:1001:1001::/var/empty:/bin/false
    '')
    (pkgs.writeTextDir "etc/group" ''
      root:x:0:
      nobody:x:65534:
      nogroup:x:65533:
      grocy:x:1000:
      nginx:x:1001:
    '')
    (pkgs.writeTextDir "etc/nsswitch.conf" ''
      passwd: files
      group: files
      shadow: files
    '')
    (pkgs.writeTextDir "etc/grocy/config.php" ''
      <?php
      Setting('CULTURE', 'en');
      Setting('CURRENCY', 'USD');
      Setting('CALENDAR_FIRST_DAY_OF_WEEK', '1');
      Setting('CALENDAR_SHOW_WEEK_OF_YEAR', false);
    '')
  ];

  enableFakechroot = true;

  fakeRootCommands = ''
    ${pkgs.buildPackages.coreutils}/bin/mkdir -p /run/phpfpm
    ${pkgs.buildPackages.coreutils}/bin/mkdir -p /var/lib/grocy
  '';

  config = {
    Entrypoint = ["${entrypoint}"];
    ExposedPorts = { "80/tcp" = {}; };
  };
}