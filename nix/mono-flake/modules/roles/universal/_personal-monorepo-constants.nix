{ machine-config, ...}:

let
  personalMonorepoLocation = "${machine-config.userBase}/${machine-config.username}/PersonalMonorepo";

  atilsHelmDir = "${personalMonorepoLocation}/kubernetes/helm-charts";
in

{
  variables = {
    PERSONAL_MONOREPO_LOCATION = personalMonorepoLocation;
    ATILS_HELM_DIR = atilsHelmDir;
    ATILS_JOB_DIR = "${atilsHelmChartsDir}/jobs";
  };
}