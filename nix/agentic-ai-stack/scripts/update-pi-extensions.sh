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
#   1b. Backfills any lockfile entries that have a `resolved` registry
#       tarball URL but no `integrity` hash. npm sometimes writes `resolved`
#       without `integrity` for some entries when it regenerates a lock (in
#       this repo it shows up on the nested subtree of a dependency that
#       ships its own npm-shrinkwrap.json, e.g. @earendil-works/
#       pi-coding-agent). Whatever the cause, both fetchNpmDeps and
#       importNpmLock require `integrity` on every registry entry to build a
#       fixed-output fetch, so a lock with this gap fails the Nix build with
#       "attribute 'integrity' missing" even though the packages are
#       perfectly normal registry publishes. This step re-queries the
#       registry for the missing hash and writes it back into the lock.
#       Requires network access to the npm registry. Skips (with a warning)
#       any entry whose `resolved` isn't a plain registry tarball URL (e.g.
#       a git/tarball dependency), since those need a different fix -- see
#       git-extensions.nix / packageSourceOverrides, not this script.
#
#   1c. Recomputes the npm-dependency fixed-output hash (`npmDepsHash` in
#       ../extra-extensions.nix) needed by pkgs.buildNpmPackage/fetchNpmDeps.
#       It resets that line to the placeholder, then builds
#       `.#pi-extra-extensions` and reads the real hash out of the resulting
#       fixed-output mismatch. Driving the actual flake fetcher (rather than
#       a standalone prefetch-npm-deps CLI) guarantees the hash matches
#       whatever npmDepsFetcherVersion extra-extensions.nix pins -- a
#       standalone tool can produce a v1 hash that silently mismatches a v2
#       fetcher. The FOD hash changes whenever the dependency tree changes,
#       so it's regenerated here, making a package.json edit + this script
#       all that's required. Requires network (the fetch runs). Non-fatal:
#       if the hash can't be extracted, the placeholder is left in place and
#       the next real build fails with a mismatch that prints the value.
#
#   2. Fills in any unset ("fake") hashes in extensions/git-extensions.nix
#      by prefetching the pinned owner/repo@rev via `nix-prefetch-github`
#      and rewriting that entry's hash in place. Requires network access to
#      GitHub. Already-correctly-hashed entries (i.e. lines that don't
#      contain the placeholder fakeHash) are left untouched, so re-running
#      this is idempotent and doesn't needlessly re-fetch everything.
#
# This script edits extensions/package-lock.json, extensions/
# git-extensions.nix, and the single `npmDepsHash` line in
# extra-extensions.nix. It does not touch anything else.
set -euo pipefail

AGENTIC_AI_STACK="$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack"
EXTENSIONS_DIR="$AGENTIC_AI_STACK/extensions"
GIT_EXTENSIONS_FILE="$EXTENSIONS_DIR/git-extensions.nix"
EXTRA_EXTENSIONS_FILE="$AGENTIC_AI_STACK/extra-extensions.nix"
LOCK_FILE="$EXTENSIONS_DIR/package-lock.json"

# The placeholder hash value documented in git-extensions.nix's header
# comment as the "not yet computed" marker (nixpkgs' pkgs.lib.fakeHash,
# spelled out literally here since this is a plain bash/grep pass, not a
# Nix evaluation).
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

echo "==> Refreshing $LOCK_FILE from package.json..."
(
  cd "$EXTENSIONS_DIR"
  npm install --package-lock-only
)
echo "==> package-lock.json refreshed."

echo "==> Checking for lock entries missing 'integrity' (registry-fetched)..."

# Every "node_modules/..." entry that has a `resolved` field but no
# `integrity` field. fetchNpmDeps/importNpmLock need `integrity` on all of
# these to build fixed-output fetches; npm sometimes omits it.
mapfile -t MISSING_INTEGRITY_KEYS < <(
  jq -r '
    .packages
    | to_entries[]
    | select(.value.resolved != null and .value.integrity == null)
    | .key
  ' "$LOCK_FILE"
)

if [ "${#MISSING_INTEGRITY_KEYS[@]}" -eq 0 ]; then
  echo "==> No missing-integrity entries found."
else
  echo "==> Found ${#MISSING_INTEGRITY_KEYS[@]} entr$([ "${#MISSING_INTEGRITY_KEYS[@]}" -eq 1 ] && echo y || echo ies) missing 'integrity'; backfilling from the registry..."

  for key in "${MISSING_INTEGRITY_KEYS[@]}"; do
    resolved="$(jq -r --arg k "$key" '.packages[$k].resolved' "$LOCK_FILE")"
    version="$(jq -r --arg k "$key" '.packages[$k].version' "$LOCK_FILE")"

    # Only handle plain registry tarball URLs. A git/tarball dependency also
    # lacks `integrity` but for a different reason (it's not a registry
    # publish at all) -- that needs packageSourceOverrides or a move to
    # git-extensions.nix, not a registry re-query.
    if [[ "$resolved" != https://registry.npmjs.org/* ]]; then
      echo "!! Skipping $key: resolved URL is not a plain registry tarball ($resolved)." >&2
      echo "   This looks like a git/tarball dependency -- fix via git-extensions.nix or packageSourceOverrides instead." >&2
      continue
    fi

    # Recover the package name for `npm view`. It's everything under
    # node_modules/ up to (and including, for scoped packages) the last
    # path segment -- i.e. strip any "node_modules/.../node_modules/"
    # prefix from nesting.
    pkg_name="${key##*node_modules/}"

    echo "==> Querying registry for $pkg_name@$version..."
    integrity="$(npm view "${pkg_name}@${version}" dist.integrity 2>/dev/null || true)"

    if [ -z "$integrity" ]; then
      echo "!! Failed to fetch integrity for $pkg_name@$version (key: $key); leaving lock entry as-is." >&2
      continue
    fi

    echo "==> $key -> $integrity"
    jq --arg k "$key" --arg i "$integrity" \
      '.packages[$k].integrity = $i' \
      "$LOCK_FILE" > "$LOCK_FILE.tmp" && mv "$LOCK_FILE.tmp" "$LOCK_FILE"
  done

  echo "==> Integrity backfill complete."
fi

echo "==> Recomputing npm dependency FOD hash (npmDepsHash)..."

# Rewrites the single `npmDepsHash = "...";` line in extra-extensions.nix.
# '|' as the sed delimiter avoids clashing with '/' and '+' in SRI hashes
# (base64 contains neither '|' nor '"').
set_npm_deps_hash() {
  sed -i -E \
    's|^([[:space:]]*npmDepsHash[[:space:]]*=[[:space:]]*")[^"]*(";.*)$|\1'"$1"'\2|' \
    "$EXTRA_EXTENSIONS_FILE"
}

# Reset to the placeholder first, so the fixed-output npm-deps fetch is forced
# to recompute and report the real hash. (A stale-but-valid hash would just
# build successfully and print nothing to capture.)
set_npm_deps_hash "$FAKE_HASH"

# Build the flake attr with the fake hash: the fetch runs, then Nix reports
# the correct hash as a fixed-output mismatch. This uses the real flake
# fetcher, so the result always matches whatever npmDepsFetcherVersion
# extra-extensions.nix pins. The build is EXPECTED to fail here -- we only
# want the 'got:' hash.
build_out="$(nix build "$AGENTIC_AI_STACK#pi-extra-extensions" --no-link 2>&1 || true)"
NPM_DEPS_HASH="$(printf '%s\n' "$build_out" | grep -iE 'got:' | grep -oE 'sha256-[A-Za-z0-9+/]+=*' | head -n1 || true)"

if [[ "$NPM_DEPS_HASH" != sha256-* ]]; then
  echo "!! Could not extract npmDepsHash from the build output." >&2
  echo "   Left the placeholder in $EXTRA_EXTENSIONS_FILE; the next real build" >&2
  echo "   will fail with a fixed-output hash mismatch that prints the correct" >&2
  echo "   'got: sha256-...' value to paste into the npmDepsHash line." >&2
  echo "   (Full output of the probe build follows.)" >&2
  printf '%s\n' "$build_out" >&2
else
  echo "==> npmDepsHash -> $NPM_DEPS_HASH"
  set_npm_deps_hash "$NPM_DEPS_HASH"
fi

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