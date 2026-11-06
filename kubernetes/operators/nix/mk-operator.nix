{
  pkgs,
  lib,
  n2c,
  self,
  name,
  src,
}:

let
  ##############################################################################
  # 1. vendor-hash.nix handling
  #
  #  - Missing file -> explicit throw with a clear message, so this never
  #    fails as a confusing "path does not exist" error deep inside
  #    buildGoModule.
  #  - Wrong hash -> no special handling. Nix's normal fixed-output-derivation
  #    hash-mismatch failure already reports the correct hash to paste in;
  #    wrapping it would add nothing.
  #  - The file contains *just* a bare string literal, matching a pattern
  #    already used elsewhere outside this project.
  ##############################################################################
  vendorHashFile = src + "/vendor-hash.nix";
  vendorHash =
    if builtins.pathExists vendorHashFile then
      import vendorHashFile
    else
      throw ''
        operators/${name}: missing vendor-hash.nix.
        Run `nix build .#${name}-image` once with a placeholder
        (e.g. pkgs.lib.fakeHash), copy the reported expected hash into
        operators/${name}/vendor-hash.nix as a bare string, e.g.:

          "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      '';

  ##############################################################################
  # 2. Go binary
  #
  # Each operator is its own Go module (own go.mod/go.sum), not a subpackage
  # of a shared module, so one operator's dependency bump never forces
  # re-pinning every other operator's vendorHash.
  ##############################################################################
  binary = pkgs.buildGoModule {
    pname = name;
    version = "dev";
    inherit src;
    inherit vendorHash;
    subPackages = [ "cmd" ];

    # deepcopy (zz_generated.deepcopy.go) is generated here at build time,
    # not committed to the source tree — controller-gen needs it to exist
    # before the module compiles (api/v1alpha1 types implement
    # runtime.Object via generated DeepCopyObject methods).
    nativeBuildInputs = [
      pkgs.kubernetes-controller-tools
      pkgs.go
    ];
    preBuild = ''
      controller-gen object paths=./api/...
    '';
  };

  ##############################################################################
  # 3. CRD + RBAC generation
  #
  # Depends on annotation discipline in the Go source: controller-gen reads
  # +kubebuilder:object:root / validation markers from
  # api/v1alpha1/*_types.go, and +kubebuilder:rbac:groups=...,verbs=...
  # markers directly on reconciler methods in
  # internal/controller/*_controller.go. If a reconciler starts touching a
  # new resource type without a corresponding marker, the generated RBAC is
  # silently incomplete — this is the one place "generation" depends on
  # someone remembering to annotate, not something Nix can catch on its own.
  #
  # The paths (./api/..., ./internal/controller/...) are a convention this
  # function hard-codes: every operator under operators/ must follow this
  # layout for generation to find anything.
  #
  # Unlike the `binary` derivation, these are plain stdenv.mkDerivations, not
  # buildGoModule — but controller-gen still needs to `go list`/load the
  # operator's packages to inspect types (e.g. to confirm the Function API
  # type satisfies runtime.Object once its generated DeepCopyObject method is
  # accounted for), which means a `go` binary *and* resolvable module
  # dependencies on GOPATH, not just the controller-gen binary. So each of
  # these derivations also:
  #   - carries `pkgs.go` in nativeBuildInputs (alongside controller-gen);
  #   - copies `binary.goModules` (the same vendor directory buildGoModule
  #     produces for the `binary` derivation above, keyed off the same
  #     go.sum/vendor-hash.nix) into ./vendor and makes it writable;
  #   - sets GOFLAGS=-mod=vendor and GOPROXY=off so `go` resolves
  #     dependencies from that vendor directory instead of trying (and
  #     failing, sandboxed) to hit the network;
  #   - sets HOME/GOCACHE under $TMPDIR, since the build sandbox has no
  #     writable $HOME for `go` to use otherwise.
  # This all depends on operators/${name}/vendor-hash.nix and go.sum being
  # correct and in sync with go.mod — if they're stale or placeholders, the
  # `binary` derivation (and so `binary.goModules`, and so these) fail
  # before getting anywhere near controller-gen.
  #
  # The `crds` derivation additionally runs `controller-gen object` (the
  # same deepcopy generation the `binary` derivation's preBuild does) before
  # `controller-gen crd`: controller-gen loads the whole package graph to
  # resolve CRD schemas, and the Function API type only satisfies
  # runtime.Object (and so type-checks) once its generated
  # DeepCopyObject method exists — without it, package loading itself fails
  # before `crd` generation ever runs.
  ##############################################################################
  crds = pkgs.stdenv.mkDerivation {
    name = "${name}-crds";
    inherit src;
    nativeBuildInputs = [
      pkgs.kubernetes-controller-tools
      pkgs.go
    ];
    buildPhase = ''
      runHook preBuild
      cp -r ${binary.goModules} vendor
      chmod -R u+w vendor
      export GOFLAGS=-mod=vendor
      export GOPROXY=off
      export HOME=$TMPDIR
      export GOCACHE=$TMPDIR/go-cache
      controller-gen object paths=./api/...
      controller-gen crd paths=./api/... output:crd:dir=$out
      runHook postBuild
    '';
    dontInstall = true;
  };

  rbac = pkgs.stdenv.mkDerivation {
    name = "${name}-rbac";
    inherit src;
    nativeBuildInputs = [
      pkgs.kubernetes-controller-tools
      pkgs.go
    ];
    buildPhase = ''
      runHook preBuild
      cp -r ${binary.goModules} vendor
      chmod -R u+w vendor
      export GOFLAGS=-mod=vendor
      export GOPROXY=off
      export HOME=$TMPDIR
      export GOCACHE=$TMPDIR/go-cache
      controller-gen rbac:roleName=${name} paths=./internal/controller/... output:rbac:dir=$out
      runHook postBuild
    '';
    dontInstall = true;
  };

  ##############################################################################
  # 4. Image
  #
  # imageTag is an interim placeholder equal to chartVersion (see "Chart
  # assembly" below): every build gets a tag equal to its own chart
  # version for now. This is meant to be replaced by an auto-incrementing
  # semver scheme once charts are actually published; for now it just
  # needs to be a stable, resolvable tag.
  ##############################################################################
  chartVersion =
    if builtins.pathExists (src + "/VERSION") then
      lib.fileContents (src + "/VERSION")
    else
      self.shortRev or self.dirtyShortRev; # tree has uncommitted changes

  imageTag = chartVersion;

  image = n2c.buildImage {
    inherit name;
    tag = imageTag;
    config.entrypoint = [ "${binary}/bin/cmd" ];
  };

  ##############################################################################
  # 5. Chart assembly
  ##############################################################################
  hasOverrideChart = builtins.pathExists (src + "/chart");

  # Keys here are *owned* by the generated side (see the ownership note
  # below) — chart/values.yaml must never declare image.tag or
  # chart.version.
  generatedValues = pkgs.writeText "${name}-generated-values.json" (
    builtins.toJSON {
      image = {
        tag = imageTag;
      };
      chart = {
        version = chartVersion;
      };
    }
  );

  chart = pkgs.stdenv.mkDerivation {
    name = "${name}-chart";
    nativeBuildInputs = [
      pkgs.kubernetes-helm
      pkgs.yq-go
      pkgs.go
    ];
    unpackPhase = "true"; # no source archive to unpack — this derivation
    # assembles its output entirely from other
    # derivations plus the operator's own chart/ dir.
    buildPhase = ''
      runHook preBuild

      mkdir -p $out/crds $out/templates/generated

      # crds/ is copied verbatim, never templated. Helm treats this
      # directory specially: not run through the template engine, and
      # deliberately not touched by helm upgrade/uninstall.
      cp -r ${crds}/. $out/crds/

      # Generated Kubernetes objects (RBAC, manager Deployment) live under
      # templates/generated/, kept visually separate from hand-authored
      # templates so nobody mistakes one for the other. They use static
      # resource names rather than release-name-prefixed ones — an accepted
      # trade-off since each operator is installed once per cluster.
      cp ${rbac}/role.yaml $out/templates/generated/role.yaml
      cp ${./templates/manager.yaml} $out/templates/generated/manager.yaml

      ${lib.optionalString hasOverrideChart ''
        mkdir -p $out/templates
        cp -r ${src}/chart/templates/. $out/templates/
      ''}

      # Chart.yaml is never read from operators/${name}/chart/ — always
      # synthesized here. No per-operator Chart.yaml to maintain.
      cat > $out/Chart.yaml <<EOF
      apiVersion: v2
      name: ${name}
      version: 0.0.1
      appVersion: "${chartVersion}"
      EOF

      # values.yaml merge is structured around key *ownership*, not
      # merge-precedence. chart.version is always Nix-owned; image.tag is
      # a Nix-supplied default only (set here so the chart is installable
      # out of the box), which --set/--set-string or an operator's own
      # chart/values.yaml is free to override. Either way, operator
      # chart/values.yaml must never itself declare image.tag or
      # chart.version — this never has to depend on yq's left/right
      # precedence semantics to get correct behavior.
      yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' \
        ${generatedValues} \
        ${if hasOverrideChart then "${src}/chart/values.yaml" else generatedValues} \
        > $out/values.yaml

      helm package $out --destination $out/packaged

      runHook postBuild
    '';
    installPhase = "true";
  };

in
{
  inherit
    binary
    crds
    rbac
    image
    chart
    ;
}
