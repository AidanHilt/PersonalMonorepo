{ machine-config, ...}:

let
  personalMonorepoLocation = "${machine-config.userBase}/${machine-config.username}/PersonalMonorepo";

  atilsConfigDirectory = "${machine-config.userBase}/${machine-config.username}/.atils";
  atilsHelmDir = "${personalMonorepoLocation}/kubernetes/helm-charts";

  keepassDir = "${machine-config.userBase}/${machine-config.username}/KeePass";
  keepassKeyFilePath = "${keepassDir}/MasterDatabase.key";
  keepassDBPath = "${keepassDir}/MasterDatabase.kdbx";
in

{
  variables = {
    PERSONAL_MONOREPO_LOCATION = personalMonorepoLocation;

    ATILS_HELM_DIR = atilsHelmDir;
    ATILS_JOB_DIR = "${atilsHelmDir}/jobs";
    ATILS_CONFIG_DIRECTORY = "${atilsConfigDirectory}";

    KEEPASS_KEY_FILE_PATH = "${keepassKeyFilePath}";
    KEEPASS_DB_PATH = "${keepassDBPath}";
  };
}