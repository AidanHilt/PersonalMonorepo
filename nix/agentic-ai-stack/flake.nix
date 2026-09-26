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

    pi-anthropic-auth = {
      url = "github:gotgenes/pi-anthropic-auth";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, nix2container, pi-packages, pi-anthropic-auth }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        n2c = nix2container.packages.${system}.nix2container;

        mkPiPackageFromSrc = (import ./pi-packages.nix { inherit pkgs; src = pi-packages; }).mkPiPackageFromSrc;

        piPackages = (import ./pi-packages.nix { inherit pkgs; src = pi-packages; }).pi-packages
          // { pi-anthropic-auth = (mkPiPackageFromSrc
            { pname = "pi-anthropic-auth"; pnpmHash = "sha256-9yRXg2X2db+r7C7BEMu/HsXesXTIF7fTrkzkyWEs6u4="; version = "3.3.2"; src = pi-anthropic-auth;
            workspace = (builtins.fromJSON (builtins.readFile "${pi-anthropic-auth}/package.json")).name;});};

        # ---- Fixed, non-content-hash tags -----------------------------
        # A static compose.yaml needs tags that don't change on every
        # rebuild (nix2container's default tag *is* a content hash of the
        # image, which would force editing compose.yaml on every build).
        piTag = "dev";
        proxyTag = "dev";
        piImageName = "pi-sandbox/pi";
        proxyImageName = "pi-sandbox/proxy";

        pi = import ./containers/pi/image.nix {
          inherit pkgs n2c piPackages;
          imageName = piImageName;
          imageTag = piTag;
        };

        proxy = import ./containers/proxy/image.nix {
          inherit pkgs n2c;
          imageName = proxyImageName;
          imageTag = proxyTag;
        };

        # ---- helper: load an image into the local Docker daemon using
        # nix2container's built-in `copyToDockerDaemon` app. Since everything
        # runs on a NixOS VM now, we can rely on a standard Docker daemon/socket
        # instead of the old Colima-specific skopeo push-to-registry dance.
        mkLoadApp = imageName: imageTag:
        let
          linuxSystem = "x86_64-linux";
        in
        pkgs.writeShellApplication {
          name = "load-${imageName}";

          runtimeInputs = [ pkgs.nix pkgs.docker ];

          text = ''
            set -euo pipefail

            if ! docker info >/dev/null 2>&1; then
              echo "Docker daemon is not reachable" >&2
              exit 1
            fi

            IMAGE_NAME=${pkgs.lib.escapeShellArg imageName}
            IMAGE_TAG=${pkgs.lib.escapeShellArg imageTag}

            nix run --no-write-lock-file \
              ${pkgs.lib.escapeShellArg ".#${imageName}-image.copyToDockerDaemon"}

            echo "Loaded $IMAGE_NAME:$IMAGE_TAG into the local Docker daemon"
          '';
        };
      in
      {
        packages = {
          pi-image = pi.image;
          proxy-image = proxy.image;
          default = pi.image;
          pi-packages = piPackages;
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

        setup-auth-dir = flake-utils.lib.mkApp {
          drv = pkgs.writeShellApplication {
            name = "setup-auth-dir";
            runtimeInputs = [ pkgs.coreutils ];
            text = builtins.readFile ./scripts/setup-auth-dir.sh;
          };
        };

        login = flake-utils.lib.mkApp {
          drv = pkgs.writeShellApplication {
            name = "login";
            runtimeInputs = [ pkgs.pi-coding-agent ];
            text = ''
              set -euo pipefail
              export PI_CODING_AGENT_DIR="''${PI_AUTH_DIR:-$HOME/.config/pi-sandbox/auth}"
              pi
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
