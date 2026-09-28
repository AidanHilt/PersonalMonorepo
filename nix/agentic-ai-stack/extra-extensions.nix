# extra-extensions.nix
#
# Standalone, OPT-IN convenience path for pre-built pi extensions sourced
# directly from npm and/or git, as an alternative to pi-packages.nix's
# fully-reproducible pinned-pnpm-workspace approach.
#
# This module is NOT wired into containers/pi/image.nix (or anywhere else
# in the image build). Using it trades away the reproducibility guarantees
# of pi-packages.nix -- npm-sourced extensions resolve through package.json/
# package-lock.json like any other npm project, and git-sourced ones are
# just pinned-by-rev fetchFromGitHub fetches, neither of which get the
# fetcherVersion/pnpmDeps FOD treatment pi-packages.nix's workspace gets.
#
# The user is responsible for:
#   - Deciding whether to consume this at all.
#   - Manually copying this derivation's output into their own image build
#     (e.g. `cp -r ${extraExtensions}/. ~/.pi/agent/extensions/`, mirroring
#     the per-extension copy loop image.nix already does for piPackages).
#   - Merging `packagesListFragment` into their own settings.json's
#     `packages` array by hand.
#
# See ./extensions/README.md for the day-to-day "how do I add one" workflow,
# and ./extensions/git-extensions.nix for the git-hash pinning convention
# (mirrors ./hashes.nix).

{ pkgs }:

let
  lib = pkgs.lib;

  # ---- npm-sourced extensions --------------------------------------------
  # ./extensions/package.json + ./extensions/package-lock.json are a plain
  # npm project (not pnpm -- deliberately different tooling from
  # pi-packages.nix) declaring the npm-sourced extensions to pull in.
  # pkgs.importNpmLock.buildNodeModules reads the lockfile and produces a
  # node_modules/ tree; pinning pkgs.nodejs_22 for consistency with
  # pi-packages.nix's node version pin (the sketch this was based on used a
  # generic pkgs.nodejs).
  #
  # NOTE (unverified in this environment): this assumes pkgs.importNpmLock
  # exists in this flake's pinned nixpkgs revision. It was added to
  # nixpkgs as a "nodejs.buildNpmLockFile"-alternative helper; if it's
  # missing on this nixpkgs pin, this file will fail to evaluate and will
  # need pkgs.buildNpmPackage or similar substituted instead.
  npmExtensions = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ./extensions;
    nodejs = pkgs.nodejs_22;
  };

  # Names of every npm-sourced extension as they actually landed under
  # node_modules/ (i.e. the real package name, not necessarily identical to
  # however it was specified in package.json's dependencies key).
  npmExtensionNames =
    if builtins.pathExists "${npmExtensions}/node_modules"
    then builtins.attrNames (builtins.readDir "${npmExtensions}/node_modules")
    else [ ];

  # The npm specs a user needs to merge into their own settings.json
  # `packages` array as "npm:<spec>" entries. Derived straight from
  # package.json's dependencies (name@version), since that's what a user
  # edits day to day.
  npmPackageJson = builtins.fromJSON (builtins.readFile ./extensions/package.json);
  npmExtensionSpecs =
    lib.mapAttrsToList (name: version: "${name}@${version}")
      (npmPackageJson.dependencies or { });

  # ---- git-sourced extensions ---------------------------------------------
  gitExtensions = import ./extensions/git-extensions.nix;

  # Parses "git:github.com/owner/repo@rev" -> { owner, repo, rev }.
  parseGitSpec = spec:
    let
      rest = lib.removePrefix "git:github.com/" spec;
      parts = lib.splitString "/" rest;
      owner = builtins.elemAt parts 0;
      repoRev = lib.splitString "@" (builtins.elemAt parts 1);
    in
    {
      inherit owner;
      repo = builtins.elemAt repoRev 0;
      rev = builtins.elemAt repoRev 1;
    };

  fetchGitExt = spec: hash:
    let
      parsed = parseGitSpec spec;
    in
    pkgs.fetchFromGitHub {
      inherit (parsed) owner repo rev;
      inherit hash;
    };

  gitExtFetched = builtins.mapAttrs fetchGitExt gitExtensions;

  # Directory name for each git-sourced extension: the `repo` portion of
  # the spec, NOT the full spec string (which contains `/` and `:` and
  # can't be used as a single path component).
  gitExtensionDirName = spec: (parseGitSpec spec).repo;

  # ---- combined output -----------------------------------------------------
  # Flat layout: $out/<name>/... for every extension, npm or git alike.
  # This intentionally differs from the sketch this was based on, which
  # used $out/node_modules/<name> + $out/git/github.com/<name> plus a
  # $out/node_modules/.pi-package-installed/<name> marker-file scheme.
  # The marker files are dropped here on purpose: it's unverified whether
  # pi's actual extension loader needs/expects that marker convention, and
  # the flat <name>/ layout already matches how piPackages extensions get
  # copied into ~/.pi/agent/extensions/<name>/ elsewhere in this repo (see
  # containers/pi/image.nix), so a consumer can `cp -r ${out}/. dest/` and
  # get every extension in place directly.
  extraExtensions = pkgs.runCommand "pi-extra-extensions"
    { }
    ''
      mkdir -p "$out"

      ${lib.concatStringsSep "\n" (map (name: ''
        mkdir -p "$out/${name}"
        cp -RL "${npmExtensions}/node_modules/${name}/." "$out/${name}/"
      '') npmExtensionNames)}

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList
        (spec: drv:
          let name = gitExtensionDirName spec; in
          ''
            mkdir -p "$out/${name}"
            cp -RL "${drv}/." "$out/${name}/"
          '')
        gitExtFetched)}
    '';

  # The full list of spec strings a user needs to merge by hand into their
  # own settings.json's `packages` array (see module header comment).
  # Exposed here as a plain Nix list, inspectable via:
  #   nix eval .#pi-extra-extensions.packagesListFragment
  # (a `pkgs.writeText` JSON dump is deliberately NOT produced -- the
  # sketch's full settings.json step was out of scope; a plain Nix list is
  # enough to inspect/copy from by hand.)
  packagesListFragment =
    map (spec: "npm:${spec}") npmExtensionSpecs
    ++ builtins.attrNames gitExtensions;

in
extraExtensions // { inherit packagesListFragment; }
