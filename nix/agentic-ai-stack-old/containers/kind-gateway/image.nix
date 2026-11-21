{
  pkgs,
  n2c,
  imageName,
  imageTag,
}:

# kind-gateway: a narrow TCP forwarder sidecar (plain `socat`), attached to
# both the `internal` compose network and the pre-existing external `kind`
# docker network (created by `kind` itself, external: true in
# compose.kind.yaml). It forwards only :6443 to
# qa-cluster-control-plane:6443 -- `pi` never joins the `kind` network
# directly (that network has a real route to the outside world and would
# bypass the egress proxy), so this is the only bridge between `pi`'s
# isolated `internal` network and the kind cluster's own network. See
# nix/agentic-ai-stack/IMPLEMENTERS.md's network model section and
# compose.kind.yaml for the full picture.

let
  user = "kind-gateway";
  uid = "10004";
  gid = "10004";

  passwdFile = pkgs.writeTextFile {
    name = "passwd";
    destination = "/etc/passwd";
    text = ''
      root:x:0:0:root:/root:/bin/sh
      ${user}:x:${uid}:${gid}:kind-gateway forwarder user:/var/empty:/bin/sh
    '';
  };
  groupFile = pkgs.writeTextFile {
    name = "group";
    destination = "/etc/group";
    text = ''
      root:x:0:
      ${user}:x:${gid}:
    '';
  };

  rootEnv = pkgs.buildEnv {
    name = "kind-gateway-image-root";
    paths = [
      pkgs.socat
      pkgs.coreutils
      pkgs.bash
      passwdFile
      groupFile
    ];
    pathsToLink = [
      "/bin"
      "/etc"
    ];
  };

  contentId = builtins.hashString "sha256" "${rootEnv}";
in
{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = rootEnv;

    config = {
      User = "${uid}:${gid}";
      # No shell entrypoint needed -- compose.kind.yaml's `command:` supplies
      # the full socat invocation directly (keeps the forwarding rule
      # visible/editable in compose.kind.yaml rather than baked here).
      Entrypoint = [ "/bin/socat" ];

      Labels = {
        "sh.pi-sandbox.content-id" = contentId;
      };
    };
  };

  inherit contentId;
}
