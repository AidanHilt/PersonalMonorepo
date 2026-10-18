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

      # Pulls `#include <name>` directives out of a script's text, in order.
      # Must start the line at column 0 -- no leading whitespace and no "# "
      # prefix -- so prose referencing "#include" inside an ordinary comment
      # (e.g. "# Usage: declare \"#include foo\"") does not match.
      parseIncludes =
        text:
        let
          lines = lib.splitString "\n" text;
          matches = map (l: builtins.match "#include ([A-Za-z0-9_-]+)[[:space:]]*" l) lines;
        in
        map builtins.head (builtins.filter (m: m != null) matches);

      # Extracts function names a script/lib text defines, best-effort, for
      # the duplicate-definition check below. Matches "name()" and
      # "function name" starting at column 0 (no leading whitespace -- this
      # is a textual scan, not a parser, so indented/conditional function
      # definitions are missed, which is an accepted limitation).
      parseFunctionNames =
        text:
        let
          lines = lib.splitString "\n" text;
          tryMatch =
            l:
            let
              m1 = builtins.match "([A-Za-z0-9_:.-]+)[[:space:]]*\\(\\).*" l;
              m2 = builtins.match "function[[:space:]]+([A-Za-z0-9_:.-]+).*" l;
            in
            if m1 != null then m1 else m2;
          matches = map tryMatch lines;
        in
        map builtins.head (builtins.filter (m: m != null) matches);

      # Resolves the transitive closure of `#include` directives for a
      # script, in dependency-first (post-order) order, each lib emitted at
      # most once, and checks for cycles and duplicate function definitions
      # along the way. `name` is the owning script's name (used only for
      # error messages); `runText` is its already-read run.sh/lib.sh text
      # (lib texts for included libs are read internally via
      # readDirScriptOfKind, which keeps the existing `./` rewrite).
      #
      # Implemented as a pure depth-first walk via a left fold over each
      # node's own includes, threading a `state = { done, order, funcs }`
      # accumulator (done: lib names already emitted; order: closure text in
      # emission order; funcs: list of { name, desc } already seen, for the
      # duplicate check) plus a `path` stack (lib names currently being
      # visited, for cycle detection) through the recursion. `pure`,
      # independent of `pkgs` -- works on text only.
      assembleScript =
        { name, runText }:
        let
          # Finds the index of `x` in list `l`, or null if absent.
          indexOf =
            l: x:
            let
              go =
                i: rest:
                if rest == [ ] then
                  null
                else if builtins.head rest == x then
                  i
                else
                  go (i + 1) (builtins.tail rest);
            in
            go 0 l;

          # Records each function name `text` defines against `state.funcs`,
          # throwing if any was already defined by a different source.
          # `sourceId` is null for the top-level script, or a lib name.
          addFuncs =
            state: sourceId: text:
            let
              sourceDesc = if sourceId == null then "script" else "lib '${sourceId}'";
              step =
                st: fname:
                let
                  prior = lib.findFirst (f: f.name == fname) null st.funcs;
                in
                if prior != null then
                  throw "scripts/${name}: function '${fname}' defined in both ${prior.desc} and ${sourceDesc}"
                else
                  st
                  // {
                    funcs = st.funcs ++ [
                      {
                        name = fname;
                        desc = sourceDesc;
                      }
                    ];
                  };
            in
            lib.foldl' step state (parseFunctionNames text);

          # Depth-first, post-order visit of one included lib: resolves its
          # own `#include`s first (dependencies before dependents), then
          # records its functions and appends its text, unless it's already
          # in `state.done`. `includerDesc` names whoever declared this
          # include, for the missing-lib error. `path` is the stack of lib
          # names currently being visited, for cycle detection.
          visitLib =
            state: path: includerDesc: libName:
            if builtins.elem libName state.done then
              state
            else if builtins.elem libName path then
              let
                idx = indexOf path libName;
                cycle = (lib.sublist idx (builtins.length path - idx) path) ++ [ libName ];
              in
              throw "scripts/${name}: include cycle: ${lib.concatStringsSep " -> " cycle}"
            else
              let
                libEntry =
                  libByName.${libName}
                    or (throw "scripts/${name}: ${includerDesc} includes '${libName}' which does not match any lib.sh directory");
                libText = readDirScriptOfKind "lib.sh" libEntry.dir;
                deps = parseIncludes libText;
                newPath = path ++ [ libName ];
                state1 = lib.foldl' (st: d: visitLib st newPath "lib '${libName}'" d) state deps;
                state2 = addFuncs state1 libName libText;
              in
              state2
              // {
                done = state2.done ++ [ libName ];
                order = state2.order ++ [ (libText + "\n") ];
              };

          initState = {
            done = [ ];
            order = [ ];
            funcs = [ ];
          };
          topIncludes = parseIncludes runText;
          stateAfterIncludes = lib.foldl' (st: d: visitLib st [ ] "the script" d) initState topIncludes;
          finalState = addFuncs stateAfterIncludes null runText;
        in
        lib.concatStrings finalState.order + runText;

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
            in
            pkgs.writeShellApplication {
              name = e.name;
              text = assembleScript {
                name = e.name;
                inherit runText;
              };
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
