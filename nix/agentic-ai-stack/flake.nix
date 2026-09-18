{
  description = "Pi sandbox stack: containerized Pi coding agent + egress-gated proxy + native Ollama";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # nlewo/nix2container gives us buildImage + copyToDockerDaemon without
    # needing a full OCI toolchain, and produces reproducible layers.
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pi-packages = {
      url = "github:gotgenes/pi-packages";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, nix2container, pi-packages }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        n2c = nix2container.packages.${system}.nix2container;

        # ---- Fixed, non-content-hash tags -----------------------------
        # A static compose.yaml needs tags that don't change on every
        # rebuild (nix2container's default tag *is* a content hash of the
        # image, which would force editing compose.yaml on every build).
        piTag = "dev";
        proxyTag = "dev";
        piImageName = "pi-sandbox/pi";
        proxyImageName = "pi-sandbox/proxy";

        pi = import ./containers/pi/image.nix {
          inherit pkgs n2c;
          piPackages = import ./pi-packages.nix { inherit pkgs; src = pi-packages; };
          imageName = piImageName;
          imageTag = piTag;
        };

        proxy = import ./containers/proxy/image.nix {
          inherit pkgs n2c;
          imageName = proxyImageName;
          imageTag = proxyTag;
        };

        # ---- helper: load an image tarball into the local Docker daemon
        # via `docker load`. This is more portable across Colima/NixOS
        # Docker setups than nix2container's own copyToDockerDaemon
        # skopeo-based push, and makes the "confirm active Docker context"
        # step explicit and scriptable.
        mkLoadApp = imageName: imageTag:
          let
            linuxSystem = "x86_64-linux";
          in
          pkgs.writeShellApplication {
            name = "load-${imageName}";

            runtimeInputs = [
              nix2container.packages.${system}.skopeo-nix2container
              pkgs.nix
            ];

            text = ''
            set -euo pipefail

            if ! command -v colima >/dev/null 2>&1; then
              print_error "colima is not installed"
              exit 1
            fi

            if ! colima status >/dev/null 2>&1; then
              print_error "Colima is not running"
              exit 1
            fi

            IMAGE_NAME=${pkgs.lib.escapeShellArg imageName}
            IMAGE_TAG=${pkgs.lib.escapeShellArg imageTag}

            IMAGE=$(
              nix build \
                --no-link \
                --print-out-paths \
                ${pkgs.lib.escapeShellArg ".#packages.${linuxSystem}.${imageName}-image"}
            )

            echo "$IMAGE"

            DOCKER_HOST="unix://$HOME/.colima/default/docker.sock" \
              skopeo --insecure-policy copy \
                "nix:$IMAGE" \
                "docker://localhost:5000/$IMAGE_NAME:$IMAGE_TAG" \
                --dest-tls-verify=false
                #"docker-daemon:$IMAGE_NAME:$IMAGE_TAG"

            echo "Loaded $IMAGE_NAME:$IMAGE_TAG into Colima"
            '';
          };

      in
      {
        packages = {
          pi-image = pi.image;
          proxy-image = proxy.image;
          default = pi.image;
          pi-packages = import ./pi-packages.nix { inherit pkgs; src = pi-packages; };
        };

        apps = {
          # nix run .#load  -> builds + loads both images into the local
          # Docker daemon (whatever context is active: Colima or native).
          load = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "load";
              runtimeInputs = [ pkgs.docker ];
              text = ''
                set -euo pipefail
                "${(mkLoadApp "pi" "dev")}/bin/load-pi"
                "${(mkLoadApp "proxy" "dev")}/bin/load-proxy"
              '';
            };
          };

          # nix run .#start-agent -> full "up" flow, see scripts/start-agent.sh
          start-agent = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "start-agent";
              runtimeInputs = [ pkgs.docker pkgs.docker-compose pkgs.jq pkgs.gnugrep pkgs.curl pkgs.nix ];
              text = builtins.readFile ./scripts/start-agent.sh;
            };
          };

          stop-agent = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "stop-agent";
              runtimeInputs = [ pkgs.docker pkgs.docker-compose ];
              text = builtins.readFile ./scripts/stop-agent.sh;
            };
          };

          login = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "login";
              runtimeInputs = [ pkgs.docker pkgs.docker-compose ];
              text = ''
                set -euo pipefail
                cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
                docker compose --profile login run --rm login
              '';
            };
          };

          gen-kubeconfig = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "gen-kubeconfig";
              runtimeInputs = [ pkgs.kubectl pkgs.jq ];
              text = builtins.readFile ./scripts/gen-kubeconfig.sh;
            };
          };

          verify = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "verify";
              runtimeInputs = [ pkgs.docker pkgs.docker-compose pkgs.curl ];
              text = builtins.readFile ./scripts/verify-acceptance.sh;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.docker pkgs.docker-compose pkgs.nodejs_22 pkgs.jq pkgs.kubectl ];
        };
      });
}
