# git-extensions.nix
#
# Pre-built pi extensions sourced directly from git (as opposed to npm),
# for the pre-built-extensions convenience path (see ../extra-extensions.nix
# and ./README.md). Keys are "git:github.com/owner/repo@rev" specs; values
# are the fetchFromGitHub output hash for that pinned rev.
#
# To add one: add a line with `pkgs.lib.fakeHash` (or the literal string
# "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=") as the value, then
# run `nix run .#update-pi-extensions` to fill in the real hash.
#
# Generated/refreshed by nix run .#update-pi-extensions. Safe to hand-edit.

{
  # Example (commented out -- replace with a real one or remove):
  # "git:github.com/someowner/some-pi-extension@main" = "sha256-...";
}
