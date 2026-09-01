{
  description = "Shared scripts and Go binaries, auto-detected from ./scripts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      scriptsDir = ./scripts;
      lib = nixpkgs.legacyPackages.aarch64-darwin.lib;
      scriptKinds = [ "run.sh" "source.sh" "lib.sh" ];

      # Identifies which kind a script directory is (or null if it's a go
      # module / something else), reads its one script file, and rewrites
      # "./" to that directory's store path -- but only if there are other
      # files in the dir worth pointing at, so bare scripts don't pull in
      # an unnecessary store copy.
      readDirScript = dir:
        let
          entries = builtins.readDir dir;
          kind = lib.findFirst (k: builtins.hasAttr k entries) null scriptKinds;
        in
        if kind == null then null
        else
          let
            text = builtins.readFile (dir + "/${kind}");
            extras = lib.filterAttrs (n: _: n != kind) entries;
            hasExtras = extras != { };
          in
          {
            inherit kind;
            text = if hasExtras then builtins.replaceStrings [ "./" ] [ "${dir}/" ] text else text;
          };

      # Fetch + assert the expected kind, for callsites that require a specific one.
      readDirScriptOfKind = expectedKind: dir:
        let script = readDirScript dir;
        in
        assert lib.assertMsg (script != null && script.kind == expectedKind)
          "expected ${dir} to contain ${expectedKind}";
        script.text;

      # Builds { <name> = derivation; ... } plus lib-only shellcheck checks,
      # for a given `pkgs`. Kept independent of `system` so it can be reused
      # both per-system (eachDefaultSystem) and inside the overlay (which
      # only has `final`/`prev`, not a bound `pkgs`).
      mkScripts = pkgs:
        let
          entries = builtins.readDir scriptsDir;
          dirNames = builtins.attrNames (lib.filterAttrs (_: t: t == "directory") entries);

          classify = name:
            let
              files = builtins.readDir (scriptsDir + "/${name}");
              has = f: builtins.hasAttr f files;
            in
            if has "go.mod" then "go"
            else if has "run.sh" then "shell"
            else if has "lib.sh" then "lib"
            else if has "source.sh" then "source"
            else throw "scripts/${name}: expected one of go.mod, run.sh, lib.sh, source.sh";


          sourceNames = builtins.filter (n: classify n == "source") dirNames;
          libNames = builtins.filter (n: classify n == "lib") dirNames;
          pkgNames = builtins.filter (n: classify n == "go" || classify n == "shell") dirNames;

          # Pulls `# @lib: <name>` declarations out of a run.sh, in order.
          parseLibDeps = text:
            let
              lines = lib.splitString "\n" text;
              matches = map (l: builtins.match "# @lib: ([A-Za-z0-9_-]+)" l) lines;
            in
            builtins.filter (m: m != null) (map (m: if m == null then null else builtins.head m) matches);

          mkGo = name:
            let
              dir = scriptsDir + "/${name}";
              files = builtins.readDir dir;
              hasSum = builtins.hasAttr "go.sum" files;
              vendorHashFile = dir + "/vendor-hash.nix";
            in
            pkgs.buildGoModule {
              pname = name;
              version = "0.1.0";
              src = dir;
              proxyVendor = true;
              # No go.sum means no external deps, so no vendor FOD is needed.
              # Otherwise use the pinned hash if present, else fail loud with
              # fakeHash so `nix build` / `nix-update` can tell you the real one.
              vendorHash =
                if !hasSum then null
                else if builtins.pathExists vendorHashFile then import vendorHashFile
                else lib.fakeHash;
            };

          mkShell = name:
            let
              dir = scriptsDir + "/${name}";
              runText = readDirScriptOfKind "run.sh" dir;
              libDeps = parseLibDeps runText;
              libText = lib.concatMapStrings
                (libName: (readDirScriptOfKind "lib.sh" (scriptsDir + "/${libName}")) + "\n")
                libDeps;
            in
            pkgs.writeShellApplication {
              name = name;
              text = libText + runText;
            };

          packages = builtins.listToAttrs (map
            (name: {
              inherit name;
              value = if classify name == "go" then mkGo name else mkShell name;
            })
            pkgNames);

          libChecks = builtins.listToAttrs (map
            (name: {
              name = "lib-${name}-shellcheck";
              value = pkgs.runCommand "shellcheck-${name}" { } ''
                ${pkgs.shellcheck}/bin/shellcheck ${scriptsDir + "/${name}/lib.sh"}
                touch $out
              '';
            })
            libNames);

          sourceChecks = builtins.listToAttrs (map
            (name: {
              name = "source-${name}-shellcheck";
              value = pkgs.runCommand "shellcheck-source-${name}" { } ''
                ${pkgs.shellcheck}/bin/shellcheck -s bash ${scriptsDir + "/${name}/source.sh"}
                touch $out
              '';
            })
            sourceNames);
        in
        {
          inherit packages libChecks sourceChecks;
        };

        allScriptDirs = builtins.attrNames (builtins.readDir scriptsDir);
        interactiveShellInit = lib.concatMapStrings
          (name:
            let
              dir = scriptsDir + "/${name}";
              script = readDirScript dir;
            in
            if script != null && script.kind == "source.sh"
            then script.text + "\n"
            else "")
          allScriptDirs;
    in
    flake-utils.lib.eachSystem
      (builtins.filter (s: s != "x86_64-darwin") flake-utils.lib.defaultSystems)
      (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        built = mkScripts pkgs;
        all = pkgs.symlinkJoin {
          name = "scripts-all";
          paths = builtins.attrValues built.packages;
        };
      in
      {
        packages = built.packages // {
          inherit all;
          default = all;
        };

        checks = built.packages // built.libChecks // built.sourceChecks;

        devShells = builtins.mapAttrs
          (_: pkg: pkgs.mkShell { packages = [ pkg ]; })
          built.packages
        // {
          default = pkgs.mkShell {
            packages = [ pkgs.go pkgs.shellcheck pkgs.nix-update ] ++ builtins.attrValues built.packages;
          };
        };
      }
    ) // {
      inherit interactiveShellInit;
      overlays.default = final: _prev: {
        # Nested under `ahilt-scripts` to avoid shadowing real nixpkgs names.
        # `all` is deliberately left out here; it's a packaging convenience,
        # not something that belongs in the global package set.
        ahilt-scripts = (mkScripts final).packages;
      };
    };
}
