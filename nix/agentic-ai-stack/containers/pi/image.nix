{
  pkgs,
  n2c,
  imageName,
  imageTag,
  scripts,
  agent-skills,
  skills-golang,
  skills-kubernetes,
  skills-nixos,
}:

let
  user = "pi";
  uid = "10001";
  gid = "10001";
  home = "/home/${user}";

  passwdFile = pkgs.writeTextFile {
    name = "passwd";
    destination = "/etc/passwd";
    text = ''
      root:x:0:0:root:/root:/bin/sh
      ${user}:x:${uid}:${gid}:pi sandbox user:${home}:/bin/sh
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

  # Single, self-contained seed of the entire ~/.pi tree (agent/ config
  # plus top-level files like web-search.json). At runtime the entrypoint
  # copies this into the writable ~/.pi tmpfs in one shot; the source of
  # truth stays immutable in the image. Extensions, build-time pinned
  # agent skills, and the permission-system policy are all baked into
  # their final locations here, so the entrypoint needs no rm/cp dance or
  # dynamic folder lookup.
  piSeed = pkgs.runCommand "pi-seed" { } (''
    mkdir -p $out/workspace
    mkdir -p $out/home/pi/.pi-seed/agent
    mkdir -p $out/home/pi/.pi

    # config/ is a direct, 1:1 mirror of the final ~/.pi/ tree:
    # config/agent/ mirrors ~/.pi/agent/ (settings.json, models.json,
    # AGENTS.md, agents/*, and each extension's config.json already
    # live at their final relative paths under config/agent/), and
    # config/web-search.json mirrors ~/.pi/web-search.json. So this is
    # a single recursive copy of the whole config/ tree with no
    # per-file translation.
    mkdir -p $out/home/pi/.pi-seed/agent/extensions
    cp -r --no-preserve=mode ${extraExtensions}/. $out/home/pi/.pi-seed/agent/extensions/

    # Build-time pinned agent skills (see ../../extra-skills.nix). Copied
    # in next to extensions above, before the config/ copy below -- config/
    # has no skills/ dir today, so copy order doesn't matter yet, but this
    # keeps it consistent with the extensions copy for when it does.
    mkdir -p $out/home/pi/.pi-seed/agent/skills
    cp -r --no-preserve=mode ${extraSkills}/. $out/home/pi/.pi-seed/agent/skills/

    cp -r --no-preserve=mode ${../../config}/. $out/home/pi/.pi-seed/
  '');

  # Empty placeholder directories for the persistent auth/session state.
  # These paths get named Docker volumes mounted onto them at runtime
  # (see compose.yaml); baking them into the image with the right
  # ownership/mode means Docker seeds a brand-new (empty) named volume
  # from this image content instead of defaulting to root:root, so the
  # uid:10001 process can write to them with no runtime chown step.
  piState = pkgs.runCommand "pi-state" { } ''
    mkdir -p $out/home/pi/.pi-state/auth
    mkdir -p $out/home/pi/.pi-state/sessions
  '';

  entrypoint = pkgs.writeShellApplication {
    name = "pi-entrypoint";
    runtimeInputs = [
      pkgs.pi-coding-agent

      pkgs.gitMinimal
      pkgs.coreutils
      pkgs.bash
      pkgs.socat
    ];
    text = builtins.readFile ./entrypoint.sh;
  };

  rootEnv = pkgs.buildEnv {
    name = "pi-image-root";

    paths = [
      scripts.packages.${pkgs.system}.agent-plan-create
      scripts.packages.${pkgs.system}.agent-stage
      scripts.packages.${pkgs.system}.agent-validate
      # pkg-install (nix/scripts/scripts/pkg-install) is the only client
      # of the pkg-broker sidecar service (see
      # containers/pkg-broker/README.md, PROJECT-SPEC.md). It is
      # deliberately NOT allow-listed in config/agent/extensions/
      # pi-permission-system/config.json -- bundling the binary here just
      # makes it available on PATH for a human operator to run manually
      # (e.g. via `nix run .#shell-agent`).
      scripts.packages.${pkgs.system}.pkg-install
      scripts.packages.${pkgs.system}.request-domain
      pkgs.pi-coding-agent
      pkgs.mount
      pkgs.gitMinimal
      pkgs.coreutils
      pkgs.bash
      pkgs.cacert
      pkgs.socat
      pkgs.jq
      pkgs.gnugrep
      pkgs.findutils
      passwdFile
      groupFile
      entrypoint
    ];

    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
    ];
  };

  # A cheap, non-circular fingerprint of everything that actually ends up
  # in the image (the seed tree + the runtime closure). This only
  # interpolates *input* store paths, so it never has to build anything to
  # compute, and it changes iff the image's contents would change. Used by
  # `nix run .#load` to skip re-importing into the Docker daemon when
  # nothing actually changed.
  contentId = builtins.hashString "sha256" "${piSeed}-${rootEnv}-${piState}";

  extraExtensions = import ../../extra-extensions.nix { inherit pkgs; };

  extraSkills = import ../../extra-skills.nix {
    inherit pkgs;
    agentSkills = agent-skills;
    skillsGolang = skills-golang;
    skillsKubernetes = skills-kubernetes;
    skillsNixos = skills-nixos;
  };

in

{
  image = n2c.buildImage {
    name = imageName;
    tag = imageTag;

    copyToRoot = [
      piSeed
      piState
      rootEnv
    ];

    perms = [
      {
        path = piSeed;
        regex = ".*";
        mode = "0700";
        uid = pkgs.lib.toInt uid;
        gid = pkgs.lib.toInt gid;
      }
      {
        path = piState;
        regex = ".*";
        mode = "0700";
        uid = pkgs.lib.toInt uid;
        gid = pkgs.lib.toInt gid;
      }
    ];

    config = {
      User = "${uid}:${gid}";
      WorkingDir = "/workspace";
      Entrypoint = [ "/bin/pi-entrypoint" ];

      Env = [
        "HOME=${home}"
        "PI_AGENT_DIR=${home}/.pi/agent"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NO_COLOR=0"
      ];

      Labels = {
        "sh.pi-sandbox.content-id" = contentId;
      };
    };
  };

  inherit contentId;
}
