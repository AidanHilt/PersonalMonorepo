{ lib, ... }:

let
  mkSeaweedFsBucket = bucketName: { tags ? {} }: {
    resource.seaweedfs_bucket."${bucketName}" = {
      bucket = bucketName;
      tags = {
        created_time       = "\${null_resource.${bucketName}_created_time.triggers.created_time}";
        last_modified_time = "\${timestamp()}";
        created_by         = "terraform";
      } // tags;
    };

    resource.null_resource."${bucketName}_created_time" = {
      triggers = {
        created_time = "\${timestamp()}";
      };
      lifecycle = [{
        ignore_changes = ["triggers"];
      }];
    };
  };

  vaultSecretGenerators = import ./vault-secret-generator.nix {inherit lib;};

  mkSeaweedFsUser = userName: namespaces: serviceAccounts: {readOnly ? true, buckets ? [], standalone ? true}:
    let
      accessKeyId = "AKIA\${upper(random_id.${userName}_access_key.hex)}";
      allBucketActions = [
        "s3:GetObject"
        "s3:PutObject"
        "s3:DeleteObject"
        "s3:ListBucket"
        "s3:GetBucketLocation"
      ];

      readOnlyActions = [
        "s3:GetObject"
        "s3:ListBucket"
        "s3:GetBucketLocation"
      ];

      actions = if readOnly then readOnlyActions else allBucketActions;

    # Generate resource ARNs for each bucket, or wildcard if none specified
    bucketResources = if buckets == [ ]
      then [ "arn:aws:s3:::*" "arn:aws:s3:::*/*" ]
      else lib.flatten (map (b: [
        "arn:aws:s3:::${b}"
        "arn:aws:s3:::${b}/*"
      ]) buckets);

    policy = {
      Version = "2012-10-17";
      Statement = [{
        Effect   = "Allow";
        Action   = actions;
        Resource = bucketResources;
      }];
    };

    vaultSecret = vaultSecretGenerators.mkVaultSecret "${userName}-creds" {
      inherit namespaces serviceAccounts;
      mount = "seaweedfs";
      path  = "${userName}-creds";
      data  = {
        accessKey = "\${seaweedfs_iam_access_key.${userName}-access-key.access_key_id}";
        secretKey = "\${seaweedfs_iam_access_key.${userName}-access-key.secret_access_key}";
      };
    } {inherit standalone; appendSuffix = false;};

    static = {
      resource.seaweedfs_iam_access_key."${userName}-access-key" = {
        user_name = userName;
        depends_on = [
          "seaweedfs_iam_user.${userName}"
        ];
      };

      resource.seaweedfs_iam_user_policy."${userName}" = {
        name       = "${userName}-user-policy";
        user_name  = userName;
        policy     = "\${jsonencode(${builtins.toJSON policy})}";
        depends_on = [
          "seaweedfs_iam_user.${userName}"
        ];
      };

      resource.seaweedfs_iam_user."${userName}" = {
        name = userName;
      };
    };
    in
    lib.mkMerge [
      static
      vaultSecret
    ];

  # This function creates a bucket, an IAM user, and a vault secret containing the IAM
  # user's creds. The focus in this function is less on flexibility, and more on creating
  # a very standardized part of the stack.
  mkSeaweedFsStack = stackName: {namespaces ? [], serviceAccounts ? [], standalone ? false}:
    let
      namespacesList = if namespaces == [] then [stackName] else namespaces;
      serviceAccountsList = if serviceAccounts == [] then [stackName] else serviceAccounts;

      bucketConfig = mkSeaweedFsBucket stackName {};
      userConfig = mkSeaweedFsUser stackName namespacesList serviceAccountsList {
        readOnly = false;
        buckets = [stackName];
        inherit standalone;
      };
    in
    lib.mkMerge [
      bucketConfig
      userConfig
    ];
in

{
  inherit mkSeaweedFsBucket mkSeaweedFsUser mkSeaweedFsStack;
}