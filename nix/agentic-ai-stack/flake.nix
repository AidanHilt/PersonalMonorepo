{
  description = "Pi sandbox stack: nono (Landlock/Seatbelt)-based sandboxed Pi coding agent -- work profile, launcher, approval helper, ps/attach/stop/shell wrappers, and the nono-sandbox extension/skill";

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
        extraPackages = [
          pkgs.coreutils
          pkgs.bash-completion
        ];

        # Same as flake-utils' lib.mkApp, except the app value it returns also
        # carries the underlying derivation as `drv`. flake-utils' mkApp keeps
        # only { type; program; } (verified against the pinned flake-utils
        # source), so without this there is no way for
        # checks.aggregate-check to reach an app's derivation through
        # self.apps.<name>.drv. `nix run`/`nix flake show` only read
        # type/program, so the extra attribute is invisible to them.
        mkAppWithDrv =
          { drv }:
          flake-utils.lib.mkApp { inherit drv; }
          // {
            inherit drv;
          };

        # ---- checks ----------------------------------------------------
        # agent-validate's flake contract REQUIRES an attribute named exactly
        # `checks.<system>.agent-validate` for any path at or below this
        # flake's root; without it the preflight fails (exit 24) before a
        # single check runs. The ATTRIBUTE name is therefore fixed.
        #
        # The derivation that attribute points at is deliberately named
        # `aggregate-check` (not `agent-validate`/`agent-validate-checks`) so
        # it is never confused with the `agent-validate` SCRIPT package from
        # the nix/scripts flake (wired into devShells.default below). Those
        # are unrelated: one is this flake's aggregate check, the other is
        # the validator binary that preflights and builds it.
        #
        # Explicit fixtures, not a marker-file test-discovery framework:
        # every check the aggregate covers is named below.
        fixtureChecks = {
          # approval-helper's package build runs `go test ./...` (see its
          # doCheck/checkPhase above); this named check keeps that tested
          # derivation in the aggregate even if `packages` ever drops it.
          approval-helper-tests = self.packages.${system}.approval-helper;

          # scripts/gen-profile.sh's own --self-test, run hermetically. The
          # self-test brings its own fake closure command
          # (GEN_PROFILE_CLOSURE_CMD), so neither `nix` nor `nono` is needed
          # or invoked; HOME/TMPDIR point inside the build sandbox so nothing
          # reaches host state. Do not rewrite the self-test to fit this
          # check. $out is only touched once the self-test exits successfully.
          gen-profile-self-test =
            pkgs.runCommand "gen-profile-self-test"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.jq
                ];
              }
              ''
                set -eu
                mkdir -p work/home work/tmp
                export HOME="$PWD/work/home"
                export TMPDIR="$PWD/work/tmp"
                bash ${./scripts/gen-profile.sh} --self-test
                touch $out
              '';

          # A REAL profile generated from profiles/work.base.json through
          # scripts/gen-profile.sh in its Darwin/no-closure mode. That mode is
          # host-independent (no `nix-store -qR`, no host system profile) and
          # cheap, while the Linux closure-merge path is already covered by
          # gen-profile.sh's own --self-test above. The assertions below are
          # the security-sensitive invariants that must survive any future
          # edit to the base profile: they are what makes the
          # `nix --version` allow rule and the existing environment
          # protections meaningful fixture coverage instead of documentation.
          work-profile =
            pkgs.runCommand "work-profile-check"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.jq
                ];
              }
              ''
                set -eu
                mkdir -p work/home work/tmp
                export HOME="$PWD/work/home"
                export TMPDIR="$PWD/work/tmp"

                profile="$PWD/work/profile.json"
                bash ${./scripts/gen-profile.sh} \
                  --base ${./profiles/work.base.json} \
                  --out "$profile" \
                  --webhook-url "http://127.0.0.1:65535/work-profile-check-token" \
                  --workdir "$PWD/work/workdir" \
                  --os darwin

                fail() {
                  echo "work-profile-check FAIL: $*" >&2
                  exit 1
                }

                jq empty "$profile" || fail "generated profile is not valid JSON"

                sb='.command_policies.commands.nix.from.session.sandbox'
                cmds='.command_policies.commands'

                # 1. The mediated `nix` command runs with its own scratch HOME --
                #    never the payload's real pi home.
                got_home="$(jq -r "$sb.environment.set_vars.HOME" "$profile")"
                [ "$got_home" = "/tmp/pi-nix-home" ] ||
                  fail "nix sandbox HOME is '$got_home', expected '/tmp/pi-nix-home'"

                # 2. Dynamic worktree grants must stay LITERAL tokens: nono expands
                #    @git:toplevel/@git:common-dir itself at mediated-command launch.
                jq -e "$sb.fs_read | index(\"@git:toplevel\") != null" "$profile" >/dev/null ||
                  fail "@git:toplevel is missing from the nix sandbox fs_read"
                jq -e "$sb.fs_write | index(\"@git:toplevel\") != null" "$profile" >/dev/null ||
                  fail "@git:toplevel is missing from the nix sandbox fs_write"
                jq -e "$sb.fs_read | index(\"@git:common-dir\") != null" "$profile" >/dev/null ||
                  fail "@git:common-dir is missing from the nix sandbox fs_read"

                # 3. No part of the pi user's real home may be granted to the
                #    mediated nix command, directly or by descent.
                jq -e "$sb.fs_read + $sb.fs_write | map(select(. == \"/var/lib/pi\" or startswith(\"/var/lib/pi/\"))) | length == 0" "$profile" >/dev/null ||
                  fail "nix sandbox fs_read/fs_write grants /var/lib/pi or a descendant"

                # 4. Update/system-rebuild commands stay denied from the session.
                for cmd in update nixos-rebuild darwin-rebuild home-manager nix-env nix-channel; do
                  got="$(jq -r --arg c "$cmd" "$cmds | .[\$c].from.session // \"<missing>\"" "$profile")"
                  [ "$got" = "deny" ] ||
                    fail "command policy '$cmd' session mode is '$got', expected 'deny'"
                done

                # 5. The nix invocation allow list carries the exact prefix
                #    [--version] that agent-validate's read-only version probe
                #    needs (see IMPLEMENTERS.md, "Nix daemon access").
                jq -e "$cmds.nix.from.session.invocation_policy.allow | map(select(.argv.prefix == [\"--version\"])) | length == 1" "$profile" >/dev/null ||
                  fail "the nix invocation allow list is missing the exact prefix [\"--version\"]"

                touch $out
              '';
        };

        # The flake's own checks.<system>.agent-validate aggregate.
        #
        # An empty-output marker derivation: the real work happens in
        # buildInputs, which covers EVERY derivation in packages.<system>
        # (including the nono/pi aliases and the optional extension/skill
        # bundles), every apps.<system>.<name>.drv (the launcher/wrapper
        # scripts), and every fixture check above. So one
        # `nix build .#checks.<system>.agent-validate` builds the whole flake
        # and fails if anything in it fails.
        #
        # The graph stays lazy and acyclic: packages/apps never reference
        # `checks`, and this aggregate references only packages, apps, and
        # fixtureChecks -- never the final `checks` attrset or itself.
        # Duplicate drvs (a package also reachable through an app's
        # runtimeInputs) are harmless in buildInputs.
        aggregateCheck =
          pkgs.runCommand "aggregate-check"
            {
              buildInputs =
                builtins.attrValues self.packages.${system}
                ++ map (app: app.drv) (builtins.attrValues self.apps.${system})
                ++ builtins.attrValues fixtureChecks;
            }
            ''
              touch $out
            '';
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
          #
          # Its own `go test ./...` suite (approval-helper/main_test.go) runs
          # as part of the package build. The module is stdlib-only, so the
          # tests need no network. fixtureChecks below exposes this tested
          # package under its own check name so the
          # checks.<system>.agent-validate aggregate cannot silently drop the
          # test coverage if this package is ever removed from `packages`.
          approval-helper = pkgs.buildGoModule {
            pname = "approval-helper";
            version = "0.1.0";
            src = ./approval-helper;
            vendorHash = null;

            doCheck = true;
            checkPhase = ''
              runHook preCheck
              go test ./...
              runHook postCheck
            '';
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
          start-agent = mkAppWithDrv {
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

          # nix run .#ps -> scripts/ps.sh: lists every live nono session --
          # every session in this stack now shares ONE nono XDG_STATE_HOME
          # (see lib-common.sh's nono_state_dir and IMPLEMENTERS.md's
          # "Single nono state dir" section), so this is a single `nono ps`
          # call, not a loop over per-run state dirs.
          ps = mkAppWithDrv {
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

          # nix run .#attach [-- <name>] -> scripts/attach.sh: attaches to
          # pi's own TUI session for an existing run. <name> is optional
          # when exactly one MAIN session is live (see attach.sh --help).
          attach = mkAppWithDrv {
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

          # nix run .#stop [-- <name>] -> scripts/stop.sh: stops a run and
          # releases its live-shared paths. <name> is optional when exactly
          # one candidate (live session, or leftover crashed-launch
          # bookkeeping dir) exists (see stop.sh --help).
          stop = mkAppWithDrv {
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

          # nix run .#shell [-- <name>] -> scripts/shell.sh: opens a
          # separate, interactive bash shell inside a nono sandbox for an
          # existing (or not-yet-started) run, with its own approval helper
          # (`nix run .#attach` attaches to pi's own TUI PTY instead, which
          # can't serve this purpose -- see shell.sh's header comment).
          # <name> is optional when exactly one MAIN session is live (not
          # available under --dry-run -- see shell.sh --help). Modelled on
          # apps.start-agent's wrapper shape, minus pi itself (this app never
          # runs `pi`, only a plain bash). PI_STACK_BASH_BIN comes from this
          # flake's own nixpkgs (pkgs.bashInteractive, NOT nixpkgs-unstable's
          # pi-coding-agent closure) -- see shell.sh's "bash path fallback" note.
          shell = mkAppWithDrv {
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

          gen-kubeconfig = mkAppWithDrv {
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
          update-pi-extensions = mkAppWithDrv {
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

        # checks.<system>.agent-validate is the attribute name agent-validate
        # requires (see the fixtureChecks comment above); it points at
        # `aggregate-check`, whose derivation name is deliberately distinct
        # from the agent-validate script package. The individual fixtures
        # stay exposed here for debugging:
        # `nix build .#checks.<system>.gen-profile-self-test` etc.
        checks = fixtureChecks // {
          agent-validate = aggregateCheck;
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
