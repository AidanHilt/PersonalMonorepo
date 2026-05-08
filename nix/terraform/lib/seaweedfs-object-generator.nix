{ lib, ... }:

let
  mkSeaweedFsBucket = bucketName: tags ? {}: {
    resource.seaweedfs_bucket."${bucketName}" = {
      name = bucketName;
      tags = {
        created_time       = "\${null_resource.created_time.triggers.created_at}";
        last_modified_time = "\${timestamp()}";
        created_by         = "terraform";
      } // tags;
    };

    resource.null_resource.created_time = {
      triggers = {
        created_at = "\${timestamp()}";
      };
      lifecycle = [{
        ignore_changes = ["triggers"];
      }];
    };
  };

  mkSeaweedFsUser = {userName, readOnly ? true, buckets ? []}: {

  };
in

{
  inherit mkSeaweedFsBucket;
}