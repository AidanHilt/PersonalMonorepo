{ pkgs, tag }:
let
  it-tools = pkgs.it-tools.overrideAttrs (oldAttrs: {
    buildPhase = ''
      runHook preBuild
      export BASE_URL=/it-tools
      pnpm build
      runHook postBuild
    '';
  });

  nginxMainConf = pkgs.writeText "nginx.conf" ''
    user nobody nobody;
    worker_processes auto;
    error_log /dev/stderr warn;
    daemon off;
    pid /tmp/nginx.pid;
    
    events {
      worker_connections 1024;
    }
    
    http {
      include ${pkgs.nginx}/conf/mime.types;
      default_type application/octet-stream;
      
      access_log /dev/stdout;
      
      sendfile on;
      keepalive_timeout 65;
      
      client_body_temp_path /tmp/client_body;
      proxy_temp_path /tmp/proxy;
      fastcgi_temp_path /tmp/fastcgi;
      uwsgi_temp_path /tmp/uwsgi;
      scgi_temp_path /tmp/scgi;
      
      include /etc/nginx/conf.d/*.conf;
    }
  '';

  nginxConf = pkgs.writeText "default.conf" ''
    server {
      listen 80;
      server_name localhost;
      root ${it-tools}/lib/;
      index index.html;
      
      location /it-tools/ {
        alias ${it-tools}/lib/
        try_files $uri $uri/ /it-tools/index.html;
      }

      location = /it-tools {
        return 301 /it-tools/;
      }
    }
  '';

  rootfs = pkgs.runCommand "rootfs" {} ''
    mkdir -p $out/etc/nginx/conf.d
    cp ${nginxConf} $out/etc/nginx/conf.d/default.conf
    cp ${nginxMainConf} $out/etc/nginx/nginx.conf
  '';
in
{
  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = [ it-tools pkgs.nginx pkgs.fakeNss rootfs ];
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