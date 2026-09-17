# hashes.nix
#
# The one part of default.nix that can't be derived purely from the
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
  # src = "sha256-...";   # filled in by update-hashes.sh
  packages = {
    # pi-subagents = "sha256-...";
  };
}
