# extra-extensions.nix
#
# Build pipeline for pre-built pi extensions sourced directly from npm
# and/or git. This is wired into the image build: containers/pi/image.nix
# copies this derivation's output straight into
# $out/home/pi/.pi-seed/agent/extensions/.
#
# npm-sourced extensions resolve through package.json/package-lock.json like
# any other npm project (via pkgs.buildNpmPackage's fixed-output npm cache),
# and git-sourced ones are pinned-by-rev fetchFromGitHub fetches.
#
# Native binaries: npm packages may ship prebuilt ELF binaries (.so / .node /
# executables) built against a conventional glibc layout. On a Nix-built image
# those fail to load ("cannot open shared object file" for libgcc_s/libstdc++,
# or a missing ELF interpreter). Patching is OPT-IN per extension: pass the
# extension names in `autoPatchExtensions` (npm package names as they appear in
# extensions/package.json, or git repo dir names). For each one, the final step
# of `extraExtensions` runs autoPatchelf over that extension's directory AND its
# transitive dependency closure inside the shared node_modules (native addons
# are usually hoisted optionalDependencies, not inside the extension's own dir).
# Nothing else in the output is touched. See `nativeRuntimeLibs` below for how
# to supply extra libraries.
#
# See ./extensions/README.md for the day-to-day "how do I add one" workflow,
# and ./extensions/git-extensions.nix for the git-hash pinning convention
# (a hand-editable map of "git:github.com/owner/repo@rev" specs to
# fetchFromGitHub output hashes).

{ pkgs
, # Extensions to run autoPatchelf on (see "Native binaries" above). Names are
  # package.json dependency names (e.g. "@ff-labs/pi-fff") or git repo names.
  autoPatchExtensions ? [ "@ff-labs/pi-fff" ]
}:

let
  lib = pkgs.lib;

  # ---- npm dependency FOD hash -------------------------------------------
  # Fixed-output hash of the offline npm cache that fetchNpmDeps builds from
  # ./extensions/package-lock.json (consumed by buildNpmPackage below).
  #
  # REGENERATED AUTOMATICALLY by `nix run .#update-pi-extensions` (step 1c)
  # -- do not hand-edit. It's the fixed-output hash of the npm cache, and it
  # is tied to npmDepsFetcherVersion below (change the fetcher version and
  # this must be regenerated). If it ever goes stale the build fails with a
  # fixed-output hash mismatch that prints the correct `got:` value to paste
  # in (or just re-run update-pi-extensions).
  npmDepsHash = "sha256-kiq/9P6ZPh5Ys1eTE+XJ8r6yjDunQ6riKMa4lBCirP8=";

  # ---- shared libraries for prebuilt native binaries ----------------------
  # Libraries autoPatchelf may point prebuilt binaries at. glibc itself is
  # resolved automatically by the hook; what prebuilt Rust/C++ addons usually
  # also need is the GCC runtime (libgcc_s.so.1, libstdc++.so.6), which lives in
  # stdenv.cc.cc.lib.
  #
  # If the build fails with "auto-patchelf could not satisfy dependency
  # libfoo.so.N wanted by <file>", add the package providing libfoo here
  # (e.g. pkgs.openssl, pkgs.zlib) rather than silencing the error.
  nativeRuntimeLibs = [
    pkgs.stdenv.cc.cc.lib
  ];

  # Sonames autoPatchelf should NOT fail on. npm ships both -gnu and -musl
  # variants of platform packages (e.g. @ff-labs/fff-bin-linux-arm64-musl,
  # @yuuang/ffi-rs-linux-arm64-musl); the musl builds want a musl libc that
  # doesn't exist here. Loaders on a glibc system never select them, so we leave
  # them in place (keeps the package layout intact for loaders that probe for
  # them) and just tell autoPatchelf not to fail on their missing libc.
  ignoreMissingNativeDeps = [
    "libc.musl-aarch64.so.1"
    "libc.musl-x86_64.so.1"
  ];

  # ---- npm-sourced extensions --------------------------------------------
  # ./extensions/package.json + ./extensions/package-lock.json are a plain
  # npm project declaring the npm-sourced extensions to pull in.
  #
  # We resolve them with pkgs.buildNpmPackage, whose fetchNpmDeps builds a
  # fixed-output, offline npm cache from package-lock.json and then runs a
  # normal `npm ci` against it. nodejs is pinned to pkgs.nodejs_22.
  #
  # Why NOT pkgs.importNpmLock (the more obvious "build node_modules from a
  # lockfile" helper, and what this used to use): importNpmLock rewrites
  # every lockfile `resolved` field to a file:<store-path>. That breaks for
  # any dependency shipping its own npm-shrinkwrap.json -- here
  # @earendil-works/pi-coding-agent has "hasShrinkwrap": true. npm honors
  # that inner lockfile when reifying pi-coding-agent's subtree, and its
  # entries still name registry URLs (https://registry.npmjs.org/...) that
  # importNpmLock never rewrote. With the cache in only-if-cached mode those
  # URLs resolve to no store path, so the offline `npm ci` reaches for the
  # network and dies with `npm error code ENOTCACHED`.
  #
  # fetchNpmDeps sidesteps this entirely: it pre-populates the offline cache
  # keyed by the *same registry URLs* the shrinkwrap names (every one of
  # them also appears in the top-level package-lock.json, which is what
  # fetchNpmDeps reads), so the shrinkwrap's lookups hit the cache and the
  # build stays offline. This is why it doesn't require knowing anything
  # about a given dependency's internal packaging.
  npmExtensions = pkgs.buildNpmPackage {
    pname = "pi-extra-extensions-node-modules";
    version = "0.0.0";
    src = ./extensions;
    inherit npmDepsHash;
    nodejs = pkgs.nodejs_22;

    # ./extensions is a manifest, not a buildable package -- there's no
    # build step and nothing to compile, we only want the resolved
    # node_modules/ tree. So skip `npm run build` and the default
    # `npm pack`-based install, and copy node_modules straight to $out,
    # preserving the ${npmExtensions}/node_modules/<name> layout the rest of
    # this file consumes below.
    dontNpmBuild = true;

    # fetchNpmDeps' v1 prefetcher builds the offline cacache in a way whose
    # keys don't always match npm's only-if-cached lookups -- transitive/
    # peer/scoped entries (e.g. @earendil-works/pi-tui) can end up missing,
    # which surfaces as `npm error code ENOTCACHED` at `npm ci` time even
    # though the tarball was fetched. v2 rewrote that keying to match npm, so
    # the lookups hit. (This is buildNpmPackage's own first suggested remedy
    # for that ENOTCACHED failure.) Changing this changes npmDepsHash above,
    # which is why update-pi-extensions regenerates the hash by driving this
    # very fetcher rather than a standalone tool.
    npmDepsFetcherVersion = 2;

    # Omit peerDependencies from the actual `npm ci` install (npm >=8.3's
    # --omit=peer). This is an install-time filter only -- it changes what
    # npm ci materializes into node_modules/, not what fetchNpmDeps prefetches
    # into the offline cache from package-lock.json (that's keyed off the
    # whole lockfile regardless of omit), so npmDepsHash above does NOT need
    # to be regenerated for this. The main beneficiary is
    # @earendil-works/pi-coding-agent (package-lock.json's only top-level
    # "peer": true dependency, pulled in solely to satisfy peerDependencies
    # ranges declared by @gotgenes/pi-permission-system, pi-lens, etc.) and
    # its entire duplicate AWS/Google/OpenAI SDK transitive tree -- the real
    # `pi` binary that extensions run inside of is supplied natively via
    # pkgs.pi-coding-agent in image.nix, not via this npm copy, so no
    # extension should ever require() this package at runtime. Verified by
    # inspecting a running image's ~/.pi/agent/extensions/node_modules/ tree:
    # @earendil-works, @anthropic-ai, @aws, @aws-sdk, and @google all exist
    # there as empty directories, confirming @earendil-works/pi-coding-agent
    # and @earendil-works/pi-ai (and their SDK trees) are correctly omitted
    # by --omit=peer.
    npmFlags = [ "--omit=peer" ];

    # Copy the npm cache into a writable location at build time. Doesn't
    # affect npmDepsHash; it just lets npm write its own logs (otherwise an
    # error gets buried under a secondary "can't write to _logs" message),
    # and avoids read-only-cache failures.
    makeCacheWritable = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r node_modules "$out/node_modules"
      runHook postInstall
    '';

    # If a dependency's postinstall script fails in the build sandbox (most
    # commonly because it wants network, which the sandbox denies), set:
    #   npmFlags = [ "--ignore-scripts" ];
    # The extensions here are JS; native pieces (e.g. @ff-labs/fff-bin-*,
    # @yuuang/ffi-rs-*) arrive as prebuilt optionalDependencies rather than via
    # a postinstall build, and are patched for Nix in `extraExtensions` below.
  };

  # Parsed manifest -- the single source of truth for which packages are
  # extensions (as opposed to the flattened transitive dependency tree and
  # npm's own bookkeeping that also live under node_modules/).
  npmPackageJson = builtins.fromJSON (builtins.readFile ./extensions/package.json);

  # The extensions we actually declared, straight from package.json's
  # `dependencies` keys -- NOT readDir of node_modules/. node_modules also
  # holds npm bookkeeping (.package-lock.json, .bin/) and the whole flattened
  # transitive dependency tree; only the declared deps are extensions. A
  # scoped name like "@earendil-works/pi-coding-agent" is one extension at
  # node_modules/@earendil-works/pi-coding-agent, not the "@earendil-works"
  # scope directory a naive readDir would surface.
  npmExtensionNames = builtins.attrNames (npmPackageJson.dependencies or { });

  # Directory name each npm extension is surfaced under: the package basename
  # with any npm scope stripped (@scope/name -> name). pi discovers extensions
  # by flat directory basename -- the git extensions already rely on this via
  # gitExtensionDirName, and they load -- so a scoped package must be flattened
  # or it lands nested at $out/@scope/name/ where pi won't find it (which is
  # why previously only the unscoped pi-web-access surfaced). The full scoped
  # copy still lives inside the shared node_modules for dependency resolution;
  # only this surfaced copy is flattened. NOTE: two scoped packages sharing a
  # basename (@a/foo and @b/foo) would collide here -- add disambiguation if
  # that ever comes up.
  npmExtensionDirName = name: lib.last (lib.splitString "/" name);

  # The npm specs a user needs to merge into their own settings.json
  # `packages` array as "npm:<spec>" entries. Derived straight from
  # package.json's dependencies (name@version), since that's what a user
  # edits day to day.
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

  # ---- opt-in native patching ---------------------------------------------
  # Every requested name must be a known extension, so a typo fails at eval time
  # instead of silently patching nothing.
  knownExtensionNames =
    npmExtensionNames ++ map gitExtensionDirName (builtins.attrNames gitExtensions);
  unknownPatchTargets =
    lib.filter (n: !(builtins.elem n knownExtensionNames)) autoPatchExtensions;
  patchTargets =
    assert lib.assertMsg (unknownPatchTargets == [ ])
      "extra-extensions.nix: autoPatchExtensions names unknown extension(s): ${lib.concatStringsSep ", " unknownPatchTargets}";
    autoPatchExtensions;

  # Flattened output dir for each target (scope stripped; same rule as above).
  patchTargetDirs = map npmExtensionDirName patchTargets;

  # ---- combined output -----------------------------------------------------
  # Layout: a shared $out/node_modules/ (the full hoisted dependency tree)
  # plus $out/<name>/ for every extension, npm or git alike. The shared
  # node_modules is what makes each extension's runtime `require(...)` resolve
  # (see the builder comment). This differs from the sketch this was based on,
  # which used $out/node_modules/<name> + $out/git/github.com/<name> plus a
  # $out/node_modules/.pi-package-installed/<name> marker-file scheme. The
  # marker files are dropped here on purpose: it's unverified whether pi's
  # actual extension loader needs/expects that marker convention, and the flat
  # <name>/ layout matches how containers/pi/image.nix copies this
  # derivation's output into ~/.pi/agent/extensions/<name>/ directly.
  extraExtensions = pkgs.runCommand "pi-extra-extensions"
    {
      # autoPatchelfHook is used here as a *function provider*: runCommand has
      # no fixup phase, so the hook doesn't run by itself. Sourcing it via
      # nativeBuildInputs makes the `autoPatchelf` shell function available,
      # which the builder calls explicitly at the end. (If a future nixpkgs
      # stops exposing `autoPatchelf` this way, convert this to
      # stdenv.mkDerivation with dontUnpack = true and let the hook run in
      # fixupPhase; add dontStrip/dontPatchShebangs to keep it from touching
      # node_modules contents.)
      # jq is used to walk each target's dependency closure.
      nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.jq ];

      # Where autoPatchelf looks for the sonames the binaries ask for.
      buildInputs = nativeRuntimeLibs;

      # See ignoreMissingNativeDeps above. Passed through to the hook's
      # environment; a list of sonames/patterns on current nixpkgs.
      autoPatchelfIgnoreMissingDeps = ignoreMissingNativeDeps;
    }
    ''
      mkdir -p "$out"

      # The full hoisted node_modules tree, shared by every extension. npm
      # hoists each package's dependencies to the top of node_modules rather
      # than nesting them inside the package, so copying an extension's own
      # directory alone (below) leaves its deps behind. Shipping the whole
      # tree at $out/node_modules means that once a consumer copies $out/. into
      # ~/.pi/agent/extensions/, Node resolves each extension's require(...) by
      # walking up from extensions/<name>/ to extensions/node_modules/. (An
      # extension that bundles its own node_modules/ still wins locally, so
      # this is purely additive and doesn't disturb other extensions copied
      # into the same directory.)
      cp -RL "${npmExtensions}/node_modules" "$out/node_modules"

      # Prebuilt native binaries always ship both -gnu and -musl variants for
      # a given platform (e.g. @ast-grep/napi-linux-x64-musl,
      # @ff-labs/fff-bin-linux-arm64-musl, @yuuang/ffi-rs-linux-x64-musl); the
      # image is glibc-based, so the musl copies never load and are pure
      # dead weight. Strip the whole naming convention (node_modules/@*/*-musl)
      # rather than an explicit list, so any future musl variant pulled in by
      # a lockfile bump is caught too. ignoreMissingNativeDeps above is kept
      # regardless, in case anything still probes for the removed sonames.
      chmod -R u+w "$out/node_modules"
      shopt -s nullglob
      for d in "$out"/node_modules/@*/*-musl; do
        rm -rf -- "$d"
      done
      shopt -u nullglob

      # Each declared npm extension, surfaced flat at $out/<dir>/ where pi
      # discovers extensions -- <dir> is the package basename with any npm
      # scope stripped (see npmExtensionDirName), matching the flat layout the
      # git extensions already load under. The full scoped package still lives
      # inside the shared $out/node_modules/ for dependency resolution.
      ${lib.concatStringsSep "\n" (map (name:
        let dir = npmExtensionDirName name; in ''
        mkdir -p "$out/${dir}"
        cp -RL "${npmExtensions}/node_modules/${name}/." "$out/${dir}/"
      '') npmExtensionNames)}

      # Git-sourced extensions: source only. A git checkout ships no
      # node_modules, so a git extension's own npm dependencies are installed
      # ONLY if they're also declared in extensions/package.json (so they land
      # in the shared node_modules above). Otherwise it will fail at load time
      # with "Cannot find module '<dep>'".
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList
        (spec: drv:
          let name = gitExtensionDirName spec; in
          ''
            mkdir -p "$out/${name}"
            cp -RL "${drv}/." "$out/${name}/"
          '')
        gitExtFetched)}

      # Make prebuilt native binaries loadable on Nix -- only for the extensions
      # named in autoPatchExtensions. For each: patch its flattened dir, then
      # walk package.json dependencies + optionalDependencies through the shared
      # node_modules (hoisted native addons live there, not in the extension's
      # own dir) and patch every package reached. Packages that aren't installed
      # (other-arch/OS optional deps) are skipped. `cp -RL` leaves the store
      # copies read-only, so chmod just the selected dirs before patchelf runs.
      # An unsatisfied library fails the build loudly; see nativeRuntimeLibs.
      patchDirs=()
      seenPkgs=" "
      walkDeps() {
        local pkg="$1" pj dep
        case "$seenPkgs" in *" $pkg "*) return 0;; esac
        seenPkgs="$seenPkgs$pkg "
        pj="$out/node_modules/$pkg/package.json"
        [ -f "$pj" ] || return 0
        patchDirs+=("$out/node_modules/$pkg")
        for dep in $(jq -r '((.dependencies // {}) + (.optionalDependencies // {})) | keys[]' "$pj"); do
          walkDeps "$dep"
        done
      }
      ${lib.concatStringsSep "\n" (lib.zipListsWith (name: dir: ''
        patchDirs+=("$out/${dir}")
        walkDeps "${name}"
      '') patchTargets patchTargetDirs)}

      if [ "''${#patchDirs[@]}" -gt 0 ]; then
        chmod -R u+w "''${patchDirs[@]}"
        autoPatchelf "''${patchDirs[@]}"
      fi
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
