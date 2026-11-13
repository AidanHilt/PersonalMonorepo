{
  description = "Pi sandbox stack: nono (Landlock/Seatbelt)-based sandboxed Pi coding agent (PLAN.md Phase 4a: work profile, launcher, and approval helper built; attach/ps/stop wrappers and the nono-sandbox extension/skill are Phase 4b)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";

    # Same remote ref as nix/mono-flake's `scripts` input (see
    # nix/mono-flake/flake.nix). Only wired into devShells here, so the
    # `agent-plan-create`/`agent-validate` launchers (and anything else
    # under nix/scripts) are resolvable via `nix develop` from this flake.
    # Anyone developing from within this monorepo checkout can point this
    # at their local nix/scripts checkout instead by running
    # `nix run .#scripts-shell` (see the `scripts-shell` app below), which
    # mirrors the `--override-input scripts path:...` gating in
    # nix/mono-flake/modules/roles/universal/_update.nix.
    scripts = {
      url = "github:aidanhilt/PersonalMonorepo/project-appocalypse/knative-function-operator?dir=nix/scripts";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ---- build-time pinned agent skills -----------------------------------
    # agent-skills-nix supplies ONLY its library (lib.agent-skills:
    # discoverCatalog / allowlistFor / selectSkills / mkBundle), consumed by
    # ./extra-skills.nix to build a skills bundle the exact same way
    # extra-extensions.nix builds the extensions bundle. Its home-manager
    # module and install apps are deliberately NOT used.
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Build-time skill source: samber/cc-skills-golang, a collection of Go
    # skills under skills/. Not a flake -- fetched as plain source and
    # pinned by flake.lock like any other `flake = false` input.
    skills-golang = {
      url = "github:samber/cc-skills-golang";
      flake = false;
    };

    # Build-time skill source: LukasNiessen/kubernetes-skill. SKILL.md lives
    # at the repo root (alongside references/, docs/, etc.), not under a
    # skills/ subdirectory.
    skills-kubernetes = {
      url = "github:LukasNiessen/kubernetes-skill";
      flake = false;
    };

    # Build-time skill source: michalzubkowicz/nixos-management-skill. The
    # actual skill directory is nixos-managing/ one level below the repo
    # root.
    skills-nixos = {
      url = "github:michalzubkowicz/nixos-management-skill";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      scripts,
      agent-skills,
      skills-golang,
      skills-kubernetes,
      skills-nixos,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        packages = {
          # Standalone, opt-in convenience path for pre-built npm/git
          # extensions (see extra-extensions.nix, extensions/README.md).
          # Not wired into any image/profile build here -- exposed only so
          # it's inspectable via `nix build .#pi-extra-extensions` /
          # `nix eval`. Consumed by the nono work profile once that's
          # built (Phase 3/4 of PLAN.md).
          pi-extra-extensions = import ./extra-extensions.nix { inherit pkgs; };

          # Standalone, opt-in convenience path for the build-time pinned
          # agent skills bundle (see extra-skills.nix). Same status as
          # pi-extra-extensions above.
          pi-extra-skills = import ./extra-skills.nix {
            inherit pkgs;
            agentSkills = agent-skills;
            skillsGolang = skills-golang;
            skillsKubernetes = skills-kubernetes;
            skillsNixos = skills-nixos;
          };

          # nix build .#approval-helper -> the host-side process
          # scripts/start-agent.sh starts before each `nono run` (PLAN.md
          # Phase 4a, "Approval helper (host side)"). Stdlib-only Go (no
          # go.sum), so vendorHash is null -- there is nothing to vendor.
          approval-helper = pkgs.buildGoModule {
            pname = "approval-helper";
            version = "0.1.0";
            src = ./approval-helper;
            vendorHash = null;
          };
        };

        apps = {
          # nix run .#start-agent -> scripts/start-agent.sh (PLAN.md Phase
          # 4a): starts one nono-sandboxed `pi` session as the untrusted
          # `pi` user. `nono` itself is NOT a runtimeInput here -- it's
          # expected on the invoking user's PATH already, provided
          # system-wide by mono-flake's nono overlay (see PLAN.md's "nono
          # source" decision row and nix/mono-flake's
          # modules/roles/universal/_pi-user.nix, which adds
          # `pkgs-unstable.nono` as a systemPackage) -- same precedent this
          # script also relies on for the `pi` binary itself (no
          # `pi-coding-agent` overlay/systemPackage exists yet in
          # mono-flake; see IMPLEMENTERS.md's UNVERIFIED list).
          start-agent = flake-utils.lib.mkApp {
            # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
            drv = pkgs.writeShellApplication {
              name = "start-agent";
              runtimeInputs = [
                pkgs.jq
                pkgs.git
                self.packages.${system}.approval-helper
                pkgs.coreutils
              ];
              text = builtins.readFile ./scripts/start-agent.sh;
            };
          };

          gen-kubeconfig = flake-utils.lib.mkApp {
            # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
            drv = pkgs.writeShellApplication {
              name = "gen-kubeconfig";
              runtimeInputs = [
                pkgs.kubectl
                pkgs.jq
              ];
              text = builtins.readFile ./scripts/gen-kubeconfig.sh;
            };
          };

          # nix run .#update-pi-extensions -> refreshes extensions/package-lock.json
          # and fills in unset hashes in extensions/git-extensions.nix for the
          # extensions build pipeline (see extra-extensions.nix,
          # extensions/README.md). Requires network access.
          update-pi-extensions = flake-utils.lib.mkApp {
            # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
            drv = pkgs.writeShellApplication {
              name = "update-pi-extensions";
              runtimeInputs = [
                pkgs.nodejs-slim_24
                pkgs.nix-prefetch-github
                pkgs.nix
                pkgs.gnused
                pkgs.gnugrep
                pkgs.prefetch-npm-deps
              ];
              text = builtins.readFile ./scripts/update-pi-extensions.sh;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          # yq-go (mikefarah/yq) sits alongside jq -- chosen over the
          # Python-based kislyuk/yq to avoid pulling Python into the
          # environment (see RESEARCH-NOTES.md in nix/agentic-ai-stack).
          # pkg-install/request-domain are deliberately NOT included here
          # (PLAN.md: "pkg-broker / pkg-install" decision -- removed
          # entirely from this stack).
          packages = [
            pkgs.nodejs-slim_24
            pkgs.jq
            pkgs.yq-go
            pkgs.kubectl
            scripts.packages.${system}.agent-plan-create
            scripts.packages.${system}.agent-validate
          ];
        };
      }
    );
}
