#!/usr/bin/env bash
# nix run .#update-pi-extensions -- keeps the "pre-built npm/git extensions"
# convenience path (../extra-extensions.nix, ../extensions/) in sync:
#
#   1. Regenerates extensions/package-lock.json from extensions/package.json
#      via `npm install --package-lock-only`. Requires both `npm` on PATH
#      and network access to the npm registry -- if either is unavailable
#      this step fails loudly, which is expected/fine (this whole path is
#      an opt-in convenience mechanism, not part of the reproducible build).
#
#   2. Fills in any unset ("fake") hashes in extensions/git-extensions.nix
#      by prefetching the pinned owner/repo@rev via `nix-prefetch-github`
#      and rewriting that entry's hash in place. Requires network access to
#      GitHub. Already-correctly-hashed entries (i.e. lines that don't
#      contain the placeholder fakeHash) are left untouched, so re-running
#      this is idempotent and doesn't needlessly re-fetch everything.
#
# This script does NOT touch pi-packages.nix, hashes.nix, or anything else
# in the reproducible pnpm-workspace extension pipeline.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
EXTENSIONS_DIR="$REPO_ROOT/extensions"
GIT_EXTENSIONS_FILE="$EXTENSIONS_DIR/git-extensions.nix"

# The placeholder hash value documented in git-extensions.nix's header
# comment as the "not yet computed" marker (nixpkgs' pkgs.lib.fakeHash,
# spelled out literally here since this is a plain bash/grep pass, not a
# Nix evaluation).
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

echo "==> Refreshing $EXTENSIONS_DIR/package-lock.json from package.json..."
(
  cd "$EXTENSIONS_DIR"
  npm install --package-lock-only
)
echo "==> package-lock.json refreshed."

echo "==> Scanning $GIT_EXTENSIONS_FILE for unset git extension hashes..."

# Matches lines of the form:
#   "git:github.com/owner/repo@rev" = "sha256-...";
# (ignores commented-out example lines, which start with `#`).
mapfile -t PENDING_LINES < <(
  grep -nE '^\s*"git:github\.com/[^"]+@[^"]+"\s*=\s*"'"$FAKE_HASH"'"\s*;\s*$' \
    "$GIT_EXTENSIONS_FILE" || true
)

if [ "${#PENDING_LINES[@]}" -eq 0 ]; then
  echo "==> No unset git extension hashes found; nothing to prefetch."
  exit 0
fi

for entry in "${PENDING_LINES[@]}"; do
  line_no="${entry%%:*}"
  line_content="${entry#*:}"

  spec="$(printf '%s' "$line_content" | grep -oE 'git:github\.com/[^"]+@[^"]+')"
  owner_repo="${spec#git:github.com/}"
  owner="${owner_repo%%/*}"
  repo_rev="${owner_repo#*/}"
  repo="${repo_rev%@*}"
  rev="${repo_rev##*@}"

  echo "==> Prefetching $owner/$repo@$rev..."
  new_hash="$(nix-prefetch-github "$owner" "$repo" --rev "$rev" | \
    grep -oE '"hash"\s*:\s*"[^"]+"' | \
    sed -E 's/.*"hash"\s*:\s*"([^"]+)".*/\1/')"

  if [ -z "$new_hash" ]; then
    echo "!! Failed to compute hash for $spec (line $line_no); leaving as-is." >&2
    continue
  fi

  echo "==> $spec -> $new_hash"

  sed -i "${line_no}s|${FAKE_HASH}|${new_hash}|" "$GIT_EXTENSIONS_FILE"
done

echo "==> Done."
