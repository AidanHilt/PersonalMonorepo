{ pkgs, lib, n2c, self, name, src }:

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
    if builtins.pathExists vendorHashFile
    then import vendorHashFile
    else throw ''
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
    src = src;
    inherit vendorHash;
    subPackages = [ "cmd" ];
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
  ##############################################################################
  crds = pkgs.stdenv.mkDerivation {
    name = "${name}-crds";
    src = src;
    nativeBuildInputs = [ pkgs.controller-gen ];
    buildPhase = ''
      runHook preBuild
      controller-gen crd paths=./api/... output:crd:dir=$out
      runHook postBuild
    '';
    dontInstall = true;
  };

  rbac = pkgs.stdenv.mkDerivation {
    name = "${name}-rbac";
    src = src;
    nativeBuildInputs = [ pkgs.controller-gen ];
    buildPhase = ''
      runHook preBuild
      controller-gen rbac:roleName=${name} paths=./internal/controller/... output:rbac:dir=$out
      runHook postBuild
    '';
    dontInstall = true;
  };

  ##############################################################################
  # 4. Image
  ##############################################################################
  image = n2c.buildImage {
    name = name;
    config.entrypoint = [ "${binary}/bin/cmd" ];
  };

  ##############################################################################
  # 5. Chart assembly
  ##############################################################################
  chartVersion =
    if builtins.pathExists (src + "/VERSION")
    then lib.fileContents (src + "/VERSION")
    else if self ? shortRev then self.shortRev
    else self.dirtyShortRev; # tree has uncommitted changes

  hasOverrideChart = builtins.pathExists (src + "/chart");

  # Keys here are *owned* by the generated side (see the ownership note
  # below) — chart/values.yaml must never declare image.digest or
  # chart.version.
  generatedValues = pkgs.writeText "${name}-generated-values.json" (builtins.toJSON {
    image = {
      digest = image.imageDigest; # NOTE: confirm this attribute name against
                                   # the pinned nix2container version; its
                                   # public API for retrieving the digest has
                                   # shifted across releases.
    };
    chart = {
      version = chartVersion;
    };
  });

  chart = pkgs.stdenv.mkDerivation {
    name = "${name}-chart";
    nativeBuildInputs = [ pkgs.kubernetes-helm pkgs.yq-go ];
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
      version: ${chartVersion}
      appVersion: "${chartVersion}"
      EOF

      # values.yaml merge is structured around key *ownership*, not
      # merge-precedence: chart/values.yaml should never declare a
      # Nix-computed key (image.digest, chart.version) in the first place,
      # so this never has to depend on yq's left/right precedence semantics
      # to get correct behavior.
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
  inherit binary crds rbac image chart;
}
