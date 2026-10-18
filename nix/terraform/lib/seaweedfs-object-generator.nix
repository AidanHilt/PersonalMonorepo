{ lib, ... }:

let
  mkSeaweedFsBucket =
    bucketName: environment:
    {
      tags ? { },
    }:
    {
      resource = {
        seaweedfs_bucket."${bucketName}" = {
          count = "\${var.${environment} ? 1 : 0}";
          bucket = bucketName;
          tags = {
            created_time = "\${null_resource.${bucketName}_created_time[0].triggers.created_time}";
            last_modified_time = "\${timestamp()}";
            created_by = "terraform";
          }
          // tags;
        };

        null_resource."${bucketName}_created_time" = {
          count = "\${var.${environment} ? 1 : 0}";
          triggers = {
            created_time = "\${timestamp()}";
          };
          lifecycle = [
            {
              ignore_changes = [ "triggers" ];
            }
          ];
        };
      };

      variable."${environment}" = {
        type = "bool";
        description = "Create resources based on configuration of environment ${environment}";
        default = false;
      };
    };

  vaultSecretGenerators = import ./vault-secret-generator.nix { inherit lib; };

  # userName is the (already env-unique) name used for the actual SeaweedFS IAM
  # resources. vaultKeyName is the logical key handed to mkVaultSecret, which
  # appends "-${environment}" itself, so it should NOT already contain the
  # environment (pass userName there and you'd get a doubled suffix).
  mkSeaweedFsUser =
    userName: namespaces: serviceAccounts: environment:
    {
      readOnly ? true,
      buckets ? [ ],
      standalone ? true,
      vaultKeyName ? userName,
    }:
    let
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
      bucketResources =
        if buckets == [ ] then
          [
            "arn:aws:s3:::*"
            "arn:aws:s3:::*/*"
          ]
        else
          lib.flatten (
            map (b: [
              "arn:aws:s3:::${b}"
              "arn:aws:s3:::${b}/*"
            ]) buckets
          );

      policy = {
        Version = "2012-10-17";
        Statement = [
          {
            Effect = "Allow";
            Action = actions;
            Resource = bucketResources;
          }
        ];
      };

      vaultSecret =
        vaultSecretGenerators.mkVaultSecret "${vaultKeyName}-creds"
          {
            inherit namespaces serviceAccounts;
            mount = "seaweedfs";
            path = "${vaultKeyName}-creds";
            data = {
              accessKey = "\${seaweedfs_iam_access_key.${userName}-access-key[0].access_key_id}";
              secretKey = "\${seaweedfs_iam_access_key.${userName}-access-key[0].secret_access_key}";
            };
          }
          environment
          {
            inherit standalone;
            appendSuffix = false;
          };

      static = {
        resource = {
          seaweedfs_iam_access_key."${userName}-access-key" = {
            count = "\${var.${environment} ? 1 : 0}";
            user_name = userName;
            depends_on = [
              "seaweedfs_iam_user.${userName}[0]"
            ];
          };

          seaweedfs_iam_user_policy."${userName}" = {
            count = "\${var.${environment} ? 1 : 0}";
            name = "${userName}-user-policy";
            user_name = userName;
            policy = "\${jsonencode(${builtins.toJSON policy})}";
            depends_on = [
              "seaweedfs_iam_user.${userName}[0]"
            ];
          };

          seaweedfs_iam_user."${userName}" = {
            count = "\${var.${environment} ? 1 : 0}";
            name = userName;
          };
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
  #
  # `mount` mirrors mkVaultSecret's own namespace fallback (namespaces default to
  # [value.mount or key]): pass through the vault-config entry's `mount` so the
  # namespace fallback here matches what mkVaultSecret would derive for the same
  # entry. If omitted, falls back to stackName, same as mkVaultSecret falling back
  # to key when no mount is set.
  mkSeaweedFsStack =
    stackName: environment:
    {
      namespaces ? [ ],
      serviceAccounts ? [ ],
      standalone ? false,
      mount ? null,
    }:
    let
      toList = v: if builtins.isString v then [ v ] else v;

      fallbackNamespace = if mount != null then mount else stackName;

      namespacesList = if namespaces == [ ] then [ fallbackNamespace ] else toList namespaces;
      serviceAccountsList = if serviceAccounts == [ ] then [ stackName ] else toList serviceAccounts;

      # Environment-unique name for the actual SeaweedFS bucket/IAM resources,
      # so multiple environments enabling the same vault-config entry don't
      # collide on either the terraform resource address or the real
      # bucket/IAM user name.
      uniqueName = "${stackName}-${environment}";

      bucketConfig = mkSeaweedFsBucket uniqueName environment { };
      userConfig = mkSeaweedFsUser uniqueName namespacesList serviceAccountsList environment {
        readOnly = false;
        buckets = [ uniqueName ];
        vaultKeyName = stackName;
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
