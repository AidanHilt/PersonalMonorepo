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

  pnpmDeps = "sha256-6dN//ejDQIjwCviF5/5yeAm1mohpB2MvF2O7Qi2Oj6E=";# src = "sha256-...";   # filled in by update-hashes.sh
  packages = {
    pi-subagents-worktrees = "sha256-AQmixWLTOmAefeqBPVNQdd3xpeKqga3ILWGJQI9Pa9g=";
    pi-session-tools = "sha256-t1S1t1Bs2fvUFRi2nt5FSeiRkjJV/59UQTe/HtoZHGs=";
    pi-permission-system = "sha256-FGIOa/JqAxG/id5LIxmFm/REk6bbNUqMRT0n2XKIHm4=";
    pi-permission-model-judge = "sha256-q5w7xgMx5I9eSBc+DQ5de9/+wQaVJXUvQ5XVXKAdKUM=";
    pi-nocd = "sha256-t1S1t1Bs2fvUFRi2nt5FSeiRkjJV/59UQTe/HtoZHGs=";
    pi-github-tools = "sha256-7qEDVYnWmC7z/GM2xB9XY08vOzLmUTc7DvdZ+cCoA/0=";
    pi-colgrep = "sha256-7qEDVYnWmC7z/GM2xB9XY08vOzLmUTc7DvdZ+cCoA/0=";
    pi-autoformat = "sha256-t1S1t1Bs2fvUFRi2nt5FSeiRkjJV/59UQTe/HtoZHGs=";
    # pi-subagents = "sha256-1L8wUQN3cgVJKfZ4ufOxPZF8sey9z8W/bsmp7HAsDGQ=";
  };
}
