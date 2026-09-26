# hashes.nix
#
# The one part of pi-packages.nix that can't be derived purely from the
# repo's directory listing: fixed-output-derivation hashes.
#   - `src`              covers fetching the whole pi-packages repo
#   - `packages.<dir>`   covers each package's pruned pnpm dependency
#                         fetch (different per package, since
#                         pnpmWorkspaces scopes what actually gets
#                         fetched for each one)
#
# Generated/refreshed by ./update-hashes.sh. Safe to hand-edit too --
# it's just an attrset of strings.

{

  pnpmDeps = "sha256-9yRXg2X2db+r7C7BEMu/HsXesXTIF7fTrkzkyWEs6u4=";# src = "sha256-...";   # filled in by update-hashes.sh
  packages = {
    pi-subagents-worktrees = "sha256-AQmixWLTOmAefeqBPVNQdd3xpeKqga3ILWGJQI9Pa9g=";
    pi-session-tools = "sha256-VZDxELCph4V+LkZrz0ArDwaLT5hx5Dn1asm4TYdYFsk=";
    pi-permission-system = "sha256-VZDxELCph4V+LkZrz0ArDwaLT5hx5Dn1asm4TYdYFsk=";
    pi-permission-model-judge = "sha256-VZDxELCph4V+LkZrz0ArDwaLT5hx5Dn1asm4TYdYFsk=";
    pi-nocd = "sha256-VZDxELCph4V+LkZrz0ArDwaLT5hx5Dn1asm4TYdYFsk=";
    pi-github-tools = "sha256-VZDxELCph4V+LkZrz0ArDwaLT5hx5Dn1asm4TYdYFsk=";
    pi-colgrep = "sha256-VZDxELCph4V+LkZrz0ArDwaLT5hx5Dn1asm4TYdYFsk=";
    pi-autoformat = "sha256-VZDxELCph4V+LkZrz0ArDwaLT5hx5Dn1asm4TYdYFsk=";
    # pi-subagents = "sha256-1L8wUQN3cgVJKfZ4ufOxPZF8sey9z8W/bsmp7HAsDGQ=";
  };
}
