{ pkgs, n2c, imageName, imageTag }:

# Sidecar image for the `workspace-mounter` service (compose.workspace.yaml),
# layered by start-agent.sh only when --add/--clone extras are given. Modeled
# on containers/nix-store-mounter (same CAP_SYS_ADMIN + shared-propagation
# bind trick to publish a mount to the host), but this one needs `bindfs`
# (FUSE) rather than a plain overlay mount, since it has to translate each
# source's host ownership to pi's uid:gid 10001 for READS while letting
# writes land back on the host under the real host uid:gid -- an overlay
# can't do that per-uid rewrite, bindfs can.
#
# Unlike nix-store-mounter (which just reuses the `pi` image with its
# entrypoint overridden), this is its own dedicated image: `pi`'s image has
# no need for bindfs/util-linux's `mount` and shouldn't grow to carry them.

let
  passwdFile = pkgs.writeTextFile {
    name = "passwd";
    destination = "/etc/passwd";
    text = ''
      root:x:0:0:root:/root:/bin/sh
    '';
  };

  groupFile = pkgs.writeTextFile {
    name = "group";
    destination = "/etc/group";
    text = ''
      root:x:0:
    '';
  };

  rootEnv = pkgs.buildEnv {
    name = "workspace-mounter-image-root";
    paths = [
      pkgs.bindfs
      pkgs.mount
      pkgs.coreutils
      pkgs.bash
      passwdFile
      groupFile
    ];
    pathsToLink = [ "/bin" "/etc" ];
  };

  contentId = builtins.hashString "sha256" "${rootEnv}";
in
{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = rootEnv;

    config = {
      # Needs root -- CAP_SYS_ADMIN + bindfs/mount(2) aren't usable otherwise.
      # compose.workspace.yaml also sets this explicitly for clarity.
      User = "0:0";
      Entrypoint = [ "/bin/bash" "/mount.sh" ];

      Labels = {
        "sh.pi-sandbox.content-id" = contentId;
      };
    };
  };

  inherit contentId;
}
