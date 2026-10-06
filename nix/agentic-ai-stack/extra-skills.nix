# extra-skills.nix
#
# Build-time pinned agent skills bundle for the pi image. Sibling of
# extra-extensions.nix and built/consumed the exact same way: this
# derivation's output is copied straight into
# $out/home/pi/.pi-seed/agent/skills/ by containers/pi/image.nix.
#
# Skills are sourced as plain (non-flake) git inputs pinned via flake.lock
# (see flake.nix's skills-golang / skills-kubernetes / skills-nixos
# inputs), selected/filtered through agent-skills-nix's LIBRARY ONLY
# (`agent-skills.lib.agent-skills`: discoverCatalog / allowlistFor /
# selectSkills / mkBundle) -- its home-manager module and install apps are
# intentionally unused; nothing here touches $HOME or runs an installer.
#
# pi loads skills lazily: only each skill's name + description go into the
# system prompt (~100 tokens each); the full SKILL.md body is read on
# demand when the skill is actually used. That's why the `enable` list
# below is a deliberately curated subset of cc-skills-golang (14 of its
# ~20+ skills) rather than everything available -- see RESEARCH-NOTES.md's
# "package agent skills declaratively" section for the full survey this
# list was drawn from.

{ pkgs
, agentSkills # the `agent-skills` flake input (Kyure-A/agent-skills-nix)
, skillsGolang # samber/cc-skills-golang source (flake = false)
, skillsKubernetes # LukasNiessen/kubernetes-skill source (flake = false)
, skillsNixos # michalzubkowicz/nixos-management-skill source (flake = false)
}:

let
  lib = pkgs.lib;

  # The ONLY part of agent-skills-nix consumed here -- see module header.
  # UNVERIFIED: this attribute path (`agentSkills.lib.agent-skills`) is
  # taken from the plan's description of the flake's outputs, mirroring
  # Kyure-A/agent-skills-nix's examples/local-install/flake.nix. It was
  # not independently re-read from the actual input source in this
  # session (no network/nix access -- see the implementation report).
  agentLib = agentSkills.lib.agent-skills;

  # ---- sources ------------------------------------------------------------
  # UNVERIFIED: idPrefix is deliberately omitted for every source below,
  # per explicit instruction: prefer dropping it, since (a) the skill ids
  # pulled from cc-skills-golang (golang-code-style, golang-testing, ...)
  # already carry a `golang-` prefix in their own SKILL.md frontmatter
  # `name`, so they're unique without any added namespacing, and (b) pi
  # warns when a skill's bundled directory name doesn't equal its SKILL.md
  # frontmatter `name` -- if idPrefix nests/renames the output directory
  # (e.g. golang/golang-xxx instead of a flat golang-xxx/), that mismatch
  # would trip the warning. Re-verify directory names after `nix build`
  # and flatten/adjust here if idPrefix (or its absence) doesn't produce
  # the flat layout assumed below.
  sources = {
    golang = {
      path = skillsGolang;
      subdir = "skills";
    };

    # UNVERIFIED: nixos-management-skill's only skill, nixos-managing/, is
    # one level below the repo root (not at the root, and not under a
    # fixed subdir like "skills"). No `subdir` is passed here, relying on
    # discoverCatalog doing a recursive SKILL.md scan (per the plan's
    # description of the library) to find it there anyway.
    nixos = {
      path = skillsNixos;
    };
  };

  # UNVERIFIED: whether agent-skills-nix's discoverCatalog finds a
  # root-level SKILL.md at all. kubernetes-skill ships SKILL.md directly
  # at the repo root (not nested under any subdir), which is why it is
  # NOT listed in `sources` above and is instead built by hand below
  # (`kubernetesSkill`). If discoverCatalog turns out to handle
  # root-level SKILL.md correctly, this could be simplified to a
  # `kubernetes = { path = skillsKubernetes; };` source entry plus
  # "kubernetes-skill" in `enable`, dropping the manual fallback --
  # confirm by reading agent-skills-nix's lib/sources.nix /
  # lib/selection.nix before making that change.
  catalog = agentLib.discoverCatalog sources;

  # Curated skill selection -- see module header. Golang set matches the
  # cc-skills-golang "star" tier from RESEARCH-NOTES.md; nixos-managing is
  # nixos-management-skill's single skill.
  enable = [
    "golang-code-style"
    "golang-data-structures"
    "golang-database"
    "golang-design-patterns"
    "golang-documentation"
    "golang-error-handling"
    "golang-how-to"
    "golang-modernize"
    "golang-naming"
    "golang-refactoring"
    "golang-safety"
    "golang-testing"
    "golang-troubleshooting"
    "golang-security"
    "nixos-managing"
  ];

  allowlist = agentLib.allowlistFor {
    inherit catalog sources enable;
  };

  selection = agentLib.selectSkills {
    inherit catalog allowlist sources;
    # No per-skill transforms/overrides needed -- `enable` above is
    # sufficient to pick the exact skill set.
    skills = { };
  };

  # Bundle of every agent-skills-nix-discovered skill (golang + nixos).
  # Final skill directory names inside this bundle MUST equal each
  # SKILL.md frontmatter `name` (golang-xxx, nixos-managing) -- pi warns
  # on a name/dir mismatch. Verify directory names with `nix build
  # .#pi-extra-skills` and inspecting the result before relying on this.
  discoveredBundle = agentLib.mkBundle {
    inherit pkgs selection;
  };

  # ---- kubernetes-skill (manual fallback) ----------------------------------
  # kubernetes-skill ships SKILL.md at the repo root alongside references/,
  # docs/ (book-tooling cruft), and other repo furniture (LICENSE, etc.).
  # Rather than relying on unverified root-level SKILL.md discovery (see
  # the UNVERIFIED comment on `catalog` above), copy ONLY what SKILL.md
  # itself needs. Per the plan: the frontmatter name is "kubernetes-skill",
  # and its body links into references/ -- nothing else (no docs/,
  # node_modules/, package.json, .git, .github) ships here.
  #
  # UNVERIFIED: this is based on the plan's description of the repo, not
  # on reading SKILL.md directly (no network access in this
  # implementation session). Before trusting this is complete: read
  # SKILL.md's body for every relative link it makes (grep for `](` /
  # `references/` and any other directory names) and add any additional
  # linked file/dir this is missing. If SKILL.md links to something
  # outside references/ (e.g. a specific docs/ page), add that too,
  # but do NOT bulk-copy docs/ itself (book-tooling cruft per the plan).
  kubernetesSkill = pkgs.runCommand "pi-skill-kubernetes-skill" { } ''
    mkdir -p "$out/kubernetes-skill"
    cp "${skillsKubernetes}/SKILL.md" "$out/kubernetes-skill/SKILL.md"
    if [ -d "${skillsKubernetes}/references" ]; then
      cp -r "${skillsKubernetes}/references" "$out/kubernetes-skill/references"
    fi
  '';

  # ---- combined output ------------------------------------------------------
  # Same flat layout extra-extensions.nix uses: $out/<skill-name>/... for
  # every skill, ready to be copied straight into
  # ~/.pi-seed/agent/skills/<skill-name>/ by containers/pi/image.nix.
  extraSkills = pkgs.runCommand "pi-extra-skills" { } ''
    mkdir -p "$out"
    cp -r --no-preserve=mode "${discoveredBundle}/." "$out/"
    cp -r --no-preserve=mode "${kubernetesSkill}/." "$out/"
  '';

in
extraSkills
