{ lib, inputs, pkgs, ... }:

{
  loadMergedValues = valuesFile:
    let
      valuesFilePath = inputs.personalMonorepo + "/kubernetes/helm-charts/k8s-resources/${valuesFile}/values.yaml";

      valuesJson = pkgs.runCommand "values.json" { } ''
        ${pkgs.yq-go}/bin/yq -o=json ${valuesFilePath} > $out
      '';

      values = builtins.fromJSON (builtins.readFile valuesJson);

      configDataDir = inputs.personalMonorepo + "/kubernetes/argocd/configuration-data";

      subDirs = lib.filterAttrs
        (_: type: type == "directory")
        (builtins.readDir configDataDir);

      # For each subdir: load master-stack.yaml if present, merge with base values
      loadMerged = dirName: _:
        let
          masterStackPath = configDataDir + "/${dirName}/master-stack.yaml";
        in
        if builtins.pathExists masterStackPath
        then
          let
            masterStackJson = pkgs.runCommand "master-stack-${dirName}.json" { } ''
              ${pkgs.yq-go}/bin/yq -o=json ${masterStackPath} > $out
            '';
            masterStackValues = builtins.fromJSON (builtins.readFile masterStackJson);
          in
          lib.recursiveUpdate values masterStackValues   # masterStackValues wins on conflict
        else
          values;

      mergedValues = (builtins.mapAttrs loadMerged subDirs) // {
        original = values;
      };

    in
    mergedValues;
}