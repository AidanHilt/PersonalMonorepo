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

    # Same remote ref as nix/mono-flake's `scripts` input (see
    # nix/mono-flake/flake.nix). Not wired into the built pi/proxy container
    # images -- only into devShells/apps here, so the `agent-plan-create`
    # launcher script (and anything else under nix/scripts) is resolvable
    # via `nix build`/`nix develop` from this flake. Anyone developing from
    # within this monorepo checkout can point this at their local
    # nix/scripts checkout instead by running `nix run .#scripts-shell`
    # (see the `scripts-shell` app below), which mirrors the
    # `--override-input scripts path:...` gating in
    # nix/mono-flake/modules/roles/universal/_update.nix.
    scripts = {
      url = "github:aidanhilt/PersonalMonorepo/project-lockstep/release-mgmt?dir=nix/scripts";
    };
  };

  outputs = { self, nixpkgs, flake-utils, nix2container, scripts }:
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
          inherit pkgs n2c scripts;
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
        # `contentId` is a cheap fingerprint (see containers/*/image.nix) of
        # everything that ends up in the image, computed at eval time. It's
        # baked into the image as a Docker label, so we can compare the
        # content-id we're about to build against whatever is already
        # loaded under imageName:imageTag and skip the (surprisingly not
        # free) copyToDockerDaemon step entirely when nothing changed.
        # `appSlug` selects the flake app/package to build+load (must match
        # `packages.<appSlug>-image`). `imageName` is the *actual* Docker
        # image reference (repo:tag) that ends up in the daemon, i.e. what
        # image.nix's `imageName`/`imageTag` produced -- these are NOT the
        # same string (e.g. appSlug "pi" vs image "pi-sandbox/pi"), so they
        # must be threaded through separately or the up-to-date check below
        # inspects a Docker image that never exists and "skip" never fires.
        mkLoadApp = appSlug: imageName: imageTag: contentId:
        pkgs.writeShellApplication {
          name = "load-${appSlug}";

          runtimeInputs = [ pkgs.nix pkgs.docker ];

          text = ''
            set -euo pipefail

            if ! docker info >/dev/null 2>&1; then
              echo "Docker daemon is not reachable" >&2
              exit 1
            fi

            IMAGE_NAME=${pkgs.lib.escapeShellArg imageName}
            IMAGE_TAG=${pkgs.lib.escapeShellArg imageTag}
            NEW_CONTENT_ID=${pkgs.lib.escapeShellArg contentId}

            CURRENT_CONTENT_ID="$(docker image inspect \
              --format '{{ index .Config.Labels "sh.pi-sandbox.content-id" }}' \
              "$IMAGE_NAME:$IMAGE_TAG" 2>/dev/null || true)"

            if [ -n "$CURRENT_CONTENT_ID" ] && [ "$CURRENT_CONTENT_ID" = "$NEW_CONTENT_ID" ]; then
              echo "$IMAGE_NAME:$IMAGE_TAG is already up to date (content-id $NEW_CONTENT_ID); skipping load"
              exit 0
            fi

            override_flag=()
            if [ -n "''${PERSONAL_MONOREPO_LOCATION:-}" ] && [ -d "$PERSONAL_MONOREPO_LOCATION/nix/scripts" ]; then
              override_flag=(--override-input scripts "path:$PERSONAL_MONOREPO_LOCATION/nix/scripts")
              echo "==> Using local nix/scripts checkout at $PERSONAL_MONOREPO_LOCATION/nix/scripts"
            fi

            nix run --no-write-lock-file \
              ${pkgs.lib.escapeShellArg ".#${appSlug}-image.copyToDockerDaemon"} "''${override_flag[@]}"

            echo "Loaded $IMAGE_NAME:$IMAGE_TAG into the local Docker daemon"
          '';
        };
      in
      {
        packages = {
          pi-image = pi.image;
          proxy-image = proxy.image;
          default = pi.image;

          # Standalone, opt-in convenience path for pre-built npm/git
          # extensions (see extra-extensions.nix, extensions/README.md).
          # Deliberately NOT wired into pi-image/pi.contentId or anything
          # else image-related -- exposed here only so it's inspectable
          # via `nix build .#pi-extra-extensions` / `nix eval`.
          pi-extra-extensions = import ./extra-extensions.nix { inherit pkgs; };
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
                "${(mkLoadApp "pi" piImageName piTag pi.contentId)}/bin/load-pi"
                "${(mkLoadApp "proxy" proxyImageName proxyTag proxy.contentId)}/bin/load-proxy"
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

          # nix run .#login -> builds/loads images if needed (same as
          # `nix run .#load`), then runs the containerized, on-demand OAuth
          # login flow (spec §3.4) via the `login` compose profile. auth.json
          # ends up on the `pi-auth` named volume, shared with the `pi`
          # service (see compose.yaml). Assumes it's run from within this
          # flake's checkout (same assumption `load` already makes, since it
          # resolves the `.#*-image` flake refs relative to cwd).
          login = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "login";
              runtimeInputs = [ pkgs.docker pkgs.docker-compose pkgs.nix ];
              text = ''
                set -euo pipefail

                if ! docker info >/dev/null 2>&1; then
                  echo "Docker daemon is not reachable" >&2
                  exit 1
                fi

                echo "==> Building and loading pi image into the active Docker context..."
                nix run --no-write-lock-file .#load

                echo "==> Starting the containerized login flow..."
                docker compose --profile login run --rm --service-ports login
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

          # nix run .#update-pi-extensions -> refreshes extensions/package-lock.json
          # and fills in unset hashes in extensions/git-extensions.nix for the
          # extensions build pipeline (see extra-extensions.nix,
          # extensions/README.md). Requires network access.
          update-pi-extensions = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "update-pi-extensions";
              runtimeInputs = [ pkgs.nodejs_22 pkgs.nix-prefetch-github pkgs.nix pkgs.gnused pkgs.gnugrep pkgs.prefetch-npm-deps ];
              text = builtins.readFile ./scripts/update-pi-extensions.sh;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          # yq-go (mikefarah/yq) sits alongside jq -- chosen over the
          # Python-based kislyuk/yq to avoid pulling Python into the
          # environment (see RESEARCH-NOTES.md).
          packages = [ pkgs.docker pkgs.docker-compose pkgs.nodejs_22 pkgs.jq pkgs.yq-go pkgs.kubectl scripts.packages.${system}.agent-plan-create ];
        };
      });
}
