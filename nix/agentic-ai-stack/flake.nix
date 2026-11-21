{
  description = "Pi sandbox stack: nono (Landlock/Seatbelt)-based sandboxed Pi coding agent -- work profile, launcher, approval helper, ps/attach/stop/login/shell wrappers, and the nono-sandbox extension/skill";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";

    # This stack flake -- not nix/mono-flake -- owns provisioning `pi` and
    # `nono`: plain nixpkgs-unstable, no overlay, >= 0.81.0.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

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
      nixpkgs-unstable,
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

        # Plain, un-overlaid nixpkgs-unstable -- see the nixpkgs-unstable
        # input comment above. Only `nono` and `pi-coding-agent` are drawn
        # from here; everything else in this flake stays on the pinned
        # `nixpkgs` (nixos-26.05) input.
        pkgsUnstable = import nixpkgs-unstable {
          inherit system;
        };

        # Ad-hoc packages granted read+exec access inside the nono sandbox
        # and put on PATH there, shared by apps.start-agent and apps.shell
        # (see scripts/start-agent.sh's/scripts/shell.sh's own PI_STACK_EXTRA_PKGS/
        # PI_STACK_EXTRA_PATH handling, and IMPLEMENTERS.md). gen-profile.sh
        # already closure-expands any --read path under /nix/store into
        # filesystem.read, so it needs no change for this. Currently just
        # coreutils -- the nono-sandboxed `pi` user otherwise has no
        # coreutils, since it isn't in the host system closure.
        extraPackages = [ pkgs.coreutils pkgs.bash-completion ];
      in
      {
        packages = {
          # This stack flake's own provisioning of `pi` and `nono` (see the
          # nixpkgs-unstable input comment above): plain nixpkgs-unstable,
          # NO overlay. Exposed as top-level packages (aliases) both so
          # they're independently inspectable/buildable (`nix build
          # .#nono`, `nix build .#pi-coding-agent`) and so apps.start-agent
          # below can reference concrete store paths at eval time instead
          # of relying on `command -v` against the invoking user's PATH.
          inherit (pkgsUnstable) nono pi-coding-agent;

          # Standalone, opt-in convenience path for pre-built npm/git
          # extensions (see extra-extensions.nix, extensions/README.md).
          # Not wired into any image/profile build here -- exposed only so
          # it's inspectable via `nix build .#pi-extra-extensions` /
          # `nix eval`. Consumed by the launcher at run time.
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
          # scripts/start-agent.sh starts before each `nono run`. Stdlib-only
          # Go (no go.sum), so vendorHash is null -- there is nothing to vendor.
          approval-helper = pkgs.buildGoModule {
            pname = "approval-helper";
            version = "0.1.0";
            src = ./approval-helper;
            vendorHash = null;
          };
        };

        apps = {
          # nix run .#start-agent -> scripts/start-agent.sh: starts one
          # nono-sandboxed `pi` session as the untrusted `pi` user. This
          # stack flake provisions `nono` and `pi` itself
          # (see the nixpkgs-unstable input and the `nono`/`pi-coding-agent`
          # packages above) -- their absolute store paths are exported as
          # PI_STACK_*_BIN env vars below so start-agent.sh never has to
          # fall back to `command -v` against the invoking user's PATH when
          # run via `nix run .#start-agent` (the supported entrypoint).
          start-agent = flake-utils.lib.mkApp {
            # TODO(scripts-lib): migrate to scripts.lib.mkScript (nix/scripts flake) so shared libs/#include can be used
            drv = pkgs.writeShellApplication {
              name = "start-agent";
              # lib-common.sh's share_grant/share_release use `setfacl` on
              # Linux (POSIX ACLs) and `find` (ownership-normalization
              # sweep on release); macOS's `chmod +a` equivalent is plain
              # coreutils/system `chmod`, no extra package needed there.
              runtimeInputs = [
                pkgs.jq
                pkgs.git
                self.packages.${system}.approval-helper
                pkgs.coreutils
                pkgs.findutils
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.acl ];
              text = ''
                export PI_STACK_NONO_BIN=${pkgsUnstable.nono}/bin/nono
                export PI_STACK_PI_BIN=${pkgsUnstable.pi-coding-agent}/bin/pi
                export PI_STACK_JQ_BIN=${pkgs.jq}/bin/jq
                export PI_STACK_APPROVAL_HELPER_BIN=${self.packages.${system}.approval-helper}/bin/approval-helper
                export PI_STACK_EXTRA_PKGS="${pkgs.lib.concatMapStringsSep " " (p: "${p}") extraPackages}"
                export PI_STACK_EXTRA_PATH="${pkgs.lib.makeBinPath extraPackages}"
              ''
              + builtins.readFile ./scripts/start-agent.sh;
            };
          };

          # nix run .#ps -> scripts/ps.sh: lists nono sessions across
          # every /var/lib/pi/runs/<name>/ run (there is no
          # single cross-run `nono ps` -- see ps.sh's header comment).
          ps = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "pi-sandbox-ps";
              runtimeInputs = [
                pkgs.jq
                pkgs.coreutils
              ];
              text = ''
                export PI_STACK_NONO_BIN=${pkgsUnstable.nono}/bin/nono
              ''
              + builtins.readFile ./scripts/ps.sh;
            };
          };

          # nix run .#attach -- <name> -> scripts/attach.sh: attaches to
          # pi's own TUI session for an existing run.
          attach = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "pi-sandbox-attach";
              runtimeInputs = [
                pkgs.jq
                pkgs.coreutils
              ];
              text = ''
                export PI_STACK_NONO_BIN=${pkgsUnstable.nono}/bin/nono
              ''
              + builtins.readFile ./scripts/attach.sh;
            };
          };

          # nix run .#stop -- <name> -> scripts/stop.sh: stops a run and
          # releases its live-shared paths.
          stop = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "pi-sandbox-stop";
              # lib-common.sh's share_release (undoes start-agent.sh's
              # live file sharing) needs `setfacl` on Linux plus `find`
              # for its ownership-normalization sweep -- see
              # apps.start-agent's own comment above.
              runtimeInputs = [
                pkgs.jq
                pkgs.coreutils
                pkgs.findutils
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.acl ];
              text = ''
                export PI_STACK_NONO_BIN=${pkgsUnstable.nono}/bin/nono
              ''
              + builtins.readFile ./scripts/stop.sh;
            };
          };

          # nix run .#shell -- <name> -> scripts/shell.sh: opens a separate,
          # interactive bash shell inside a nono sandbox for an existing (or
          # not-yet-started) run, with its own approval helper (`nix run
          # .#attach` attaches to pi's own TUI PTY instead, which can't serve
          # this purpose -- see shell.sh's header comment). Modelled on
          # apps.start-agent's wrapper shape, minus pi itself (this app never
          # runs `pi`, only a plain bash). PI_STACK_BASH_BIN comes from this
          # flake's own nixpkgs (pkgs.bashInteractive, NOT nixpkgs-unstable's
          # pi-coding-agent closure) -- see shell.sh's "bash path fallback" note.
          shell = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "pi-sandbox-shell";
              # lib-common.sh's share_grant/share_release (re-shares the
              # run's workdir/--add/--clone paths for this shell's
              # lifetime, then releases them) need `setfacl` on Linux
              # plus `find` for the ownership-normalization sweep -- see
              # apps.start-agent's own comment above.
              runtimeInputs = [
                pkgs.jq
                pkgs.coreutils
                pkgs.findutils
                self.packages.${system}.approval-helper
              ]
              ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.acl ];
              text = ''
                export PI_STACK_NONO_BIN=${pkgsUnstable.nono}/bin/nono
                export PI_STACK_JQ_BIN=${pkgs.jq}/bin/jq
                export PI_STACK_APPROVAL_HELPER_BIN=${self.packages.${system}.approval-helper}/bin/approval-helper
                export PI_STACK_BASH_BIN=${pkgs.bashInteractive}/bin/bash
                export PI_STACK_EXTRA_PKGS="${pkgs.lib.concatMapStringsSep " " (p: "${p}") extraPackages}"
                export PI_STACK_EXTRA_PATH="${pkgs.lib.makeBinPath extraPackages}"
              ''
              + builtins.readFile ./scripts/shell.sh;
            };
          };

          # nix run .#login -> scripts/login.sh: runs pi's native OAuth
          # login flow inside a minimal nono session.
          login = flake-utils.lib.mkApp {
            drv = pkgs.writeShellApplication {
              name = "pi-sandbox-login";
              runtimeInputs = [
                pkgs.jq
                pkgs.git
                self.packages.${system}.approval-helper
                pkgs.coreutils
              ];
              text = ''
                export PI_STACK_NONO_BIN=${pkgsUnstable.nono}/bin/nono
                export PI_STACK_PI_BIN=${pkgsUnstable.pi-coding-agent}/bin/pi
                export PI_STACK_JQ_BIN=${pkgs.jq}/bin/jq
                export PI_STACK_APPROVAL_HELPER_BIN=${self.packages.${system}.approval-helper}/bin/approval-helper
              ''
              + builtins.readFile ./scripts/login.sh;
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
          # environment.
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
