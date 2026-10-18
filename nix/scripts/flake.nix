{
  description = "Shared scripts and Go binaries, auto-detected from ./scripts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      scriptsDir = ./scripts;
      lib = nixpkgs.lib;
      scriptKinds = [
        "run.sh"
        "source.sh"
        "lib.sh"
      ];

      # Rewrites "./foo" to "<dir>/foo", but only where "./" starts a path
      # token (after whitespace, a quote, "(" or "="). A bare "./" replace
      # would also corrupt "../foo" into "..<dir>/foo".
      rewriteLocalPaths =
        dir:
        builtins.replaceStrings
          [
            "\n./"
            " ./"
            "\t./"
            "\"./"
            "'./"
            "(./"
            "=./"
          ]
          [
            "\n${dir}/"
            " ${dir}/"
            "\t${dir}/"
            "\"${dir}/"
            "'${dir}/"
            "(${dir}/"
            "=${dir}/"
          ];

      # Identifies which kind a script directory is (or null if it's a go
      # module / something else), reads its one script file, and rewrites
      # local "./" paths to that directory's store path -- but only if there
      # are other files in the dir worth pointing at, so bare scripts don't
      # pull in an unnecessary store copy.
      readDirScript =
        dir:
        let
          entries = builtins.readDir dir;
          kind = lib.findFirst (k: builtins.hasAttr k entries) null scriptKinds;
        in
        if kind == null then
          null
        else
          let
            text = builtins.readFile (dir + "/${kind}");
            extras = lib.filterAttrs (n: _: n != kind) entries;
            hasExtras = extras != { };
          in
          {
            inherit kind;
            text = if hasExtras then rewriteLocalPaths dir text else text;
          };

      # Fetch + assert the expected kind, for callsites that require a specific one.
      readDirScriptOfKind =
        expectedKind: dir:
        let
          script = readDirScript dir;
        in
        assert lib.assertMsg (
          script != null && script.kind == expectedKind
        ) "expected ${dir} to contain ${expectedKind}";
        script.text;

      # ---- Discovery -------------------------------------------------------
      # Layout (one level of grouping at most):
      #
      #   scripts/<name>/{go.mod|run.sh|lib.sh|source.sh}          -> standalone
      #   scripts/<group>/<name>/{go.mod|run.sh|lib.sh|source.sh}  -> member of <group>
      #
      # A directory with none of the marker files directly inside it is a group.
      # Names are always the leaf directory name, never prefixed by the group.
      subdirs = dir: builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir));

      classifyDir =
        dir:
        let
          has = f: builtins.hasAttr f (builtins.readDir dir);
        in
        if has "go.mod" then
          "go"
        else if has "run.sh" then
          "shell"
        else if has "lib.sh" then
          "lib"
        else if has "source.sh" then
          "source"
        else
          "group";

      mkEntry = group: dir: name: {
        inherit name dir group;
        kind = classifyDir dir;
      };

      # Flat list of { name, dir, group (null | string), kind }.
      # Directories nested inside a group that aren't themselves one of the
      # four recognized script kinds (kind == "group", meaning: a further
      # unmarked directory) are not recursed into -- nested groups aren't
      # supported -- and throw a clear error naming the offending path
      # instead of being silently dropped.
      entries = lib.concatMap (
        name:
        let
          dir = scriptsDir + "/${name}";
          kind = classifyDir dir;
        in
        if kind == "group" then
          map (
            m:
            let
              entry = mkEntry name (dir + "/${m}") m;
            in
            if entry.kind == "group" then
              throw "scripts/${name}/${m}: unrecognized directory (none of go.mod, run.sh, lib.sh, source.sh; nested groups are not supported)"
            else
              entry
          ) (subdirs dir)
        else
          [ (mkEntry null dir name) ]
      ) (subdirs scriptsDir);

      ofKind = kinds: lib.filter (e: builtins.elem e.kind kinds) entries;
      pkgEntries = ofKind [
        "go"
        "shell"
      ];
      libEntries = ofKind [ "lib" ];
      sourceEntries = ofKind [ "source" ];

      # Only groups that actually contain a runnable script get a bundle.
      groupNames = lib.unique (map (e: e.group) (lib.filter (e: e.group != null) pkgEntries));

      # Global uniqueness across every kind of name flake.nix hands out:
      # scripts, go packages, libs, source functions, and group names. Named
      # one check so a script/lib/source-function can't silently shadow a
      # group (or each other) across directories; the error names both
      # colliding paths, not just the shared name.
      namedForUniqueness =
        map (e: {
          inherit (e) name;
          path = toString e.dir;
        }) (pkgEntries ++ libEntries ++ sourceEntries)
        ++ map (g: {
          name = g;
          path = toString (scriptsDir + "/${g}");
        }) groupNames;

      globalDuplicateMessages =
        let
          byName = lib.groupBy (e: e.name) namedForUniqueness;
          dups = lib.filterAttrs (_: es: lib.length es > 1) byName;
        in
        lib.mapAttrsToList (name: es: "'${name}': " + lib.concatMapStringsSep " vs. " (e: e.path) es) dups;

      checkGlobalUnique =
        lib.assertMsg (globalDuplicateMessages == [ ])
          "scripts/: duplicate name(s) across scripts, go packages, libs, source functions, and groups:\n  ${lib.concatStringsSep "\n  " globalDuplicateMessages}";

      # Libs are addressed globally by directory name, regardless of group.
      libByName = lib.listToAttrs (map (e: lib.nameValuePair e.name e) libEntries);

      # Pulls `# @lib: <name>` declarations out of a run.sh, in order.
      parseLibDeps =
        text:
        let
          lines = lib.splitString "\n" text;
          matches = map (l: builtins.match "# @lib: ([A-Za-z0-9_-]+)[[:space:]]*" l) lines;
        in
        map builtins.head (builtins.filter (m: m != null) matches);

      # Builds { packages, leaves, libChecks, sourceChecks } for a given
      # `pkgs`. Kept independent of `system` so it can be reused both
      # per-system (eachDefaultSystem) and inside the overlay (which only has
      # `final`/`prev`, not a bound `pkgs`).
      mkScripts =
        pkgs:
        let
          mkGo =
            e:
            let
              files = builtins.readDir e.dir;
              hasSum = builtins.hasAttr "go.sum" files;
              vendorHashFile = e.dir + "/vendor-hash.nix";
            in
            pkgs.buildGoModule {
              pname = e.name;
              version = "0.1.0";
              src = e.dir;
              proxyVendor = true;
              # No go.sum means no external deps, so no vendor FOD is needed.
              # Otherwise use the pinned hash if present, else fail loud with
              # fakeHash so `nix build` / `nix-update` can tell you the real one.
              vendorHash =
                if !hasSum then
                  null
                else if builtins.pathExists vendorHashFile then
                  import vendorHashFile
                else
                  lib.fakeHash;
            };

          mkShell =
            e:
            let
              runText = readDirScriptOfKind "run.sh" e.dir;
              libDeps = parseLibDeps runText;
              libText = lib.concatMapStrings (
                libName:
                let
                  libEntry =
                    libByName.${libName}
                      or (throw "scripts/${e.name}: '# @lib: ${libName}' does not match any lib.sh directory");
                in
                (readDirScriptOfKind "lib.sh" libEntry.dir) + "\n"
              ) libDeps;
            in
            pkgs.writeShellApplication {
              name = e.name;
              text = libText + runText;
            };

          # Individual scripts, flat: packages.<script>
          leaves = lib.listToAttrs (
            map (e: lib.nameValuePair e.name (if e.kind == "go" then mkGo e else mkShell e)) pkgEntries
          );

          # One bundle per group: packages.<group>
          groups = lib.listToAttrs (
            map (
              g:
              lib.nameValuePair g (
                pkgs.symlinkJoin {
                  name = g;
                  paths = map (e: leaves.${e.name}) (lib.filter (e: e.group == g) pkgEntries);
                }
              )
            ) groupNames
          );

          libChecks = lib.listToAttrs (
            map (
              e:
              lib.nameValuePair "lib-${e.name}-shellcheck" (
                pkgs.runCommand "shellcheck-${e.name}" { } ''
                  ${pkgs.shellcheck}/bin/shellcheck ${e.dir + "/lib.sh"}
                  touch $out
                ''
              )
            ) libEntries
          );

          sourceChecks = lib.listToAttrs (
            map (
              e:
              lib.nameValuePair "source-${e.name}-shellcheck" (
                pkgs.runCommand "shellcheck-source-${e.name}" { } ''
                  ${pkgs.shellcheck}/bin/shellcheck -s bash ${e.dir + "/source.sh"}
                  touch $out
                ''
              )
            ) sourceEntries
          );
        in
        assert checkGlobalUnique;
        {
          inherit leaves libChecks sourceChecks;
          packages = leaves // groups;
        };

      interactiveShellInit = lib.concatMapStrings (
        e: (readDirScriptOfKind "source.sh" e.dir) + "\n"
      ) sourceEntries;
    in
    flake-utils.lib.eachSystem
      (builtins.filter (s: s != "x86_64-darwin") flake-utils.lib.defaultSystems)
      (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          built = mkScripts pkgs;
          # Built from the individual scripts only, so group bundles don't
          # link every binary a second time.
          all = pkgs.symlinkJoin {
            name = "scripts-all";
            paths = builtins.attrValues built.leaves;
          };
        in
        {
          packages = built.packages // {
            inherit all;
            default = all;
          };

          # Group bundles (symlinkJoins) are intentionally excluded here --
          # only individual packages plus lib/source shellcheck checks run.
          checks = built.leaves // built.libChecks // built.sourceChecks;

          devShells = builtins.mapAttrs (_: pkg: pkgs.mkShell { packages = [ pkg ]; }) built.packages // {
            default = pkgs.mkShell {
              packages = [
                pkgs.go
                pkgs.shellcheck
                pkgs.nix-update
              ]
              ++ builtins.attrValues built.leaves;
            };
          };
        }
      )
    // {
      inherit interactiveShellInit;
      overlays.default = final: _prev: {
        # Nested under `ahilt-scripts` to avoid shadowing real nixpkgs names.
        # `all` is deliberately left out here; it's a packaging convenience,
        # not something that belongs in the global package set.
        ahilt-scripts = (mkScripts final).packages;
      };
    };
}
