#!/usr/bin/env bash
#
# Regenerates hashes.nix: for each pi-packages package, resolves its
# pnpmDeps fixed-output hash by intentionally building with a wrong hash
# and reading the correct one back out of Nix's own mismatch error --
# the standard workflow for fixed-output derivations.
#
# Packages are discovered from the agentic-ai-stack flake's own outputs
# (packages.<system>.pi-packages.<package-name>), not from a local
# default.nix. Point PERSONAL_MONOREPO_LOCATION at your monorepo
# checkout before running this.
#
# Note: since the repo fetch is now a flake input, its hash is pinned by
# flake.lock rather than by hashes.nix -- there's no separate "src" hash
# step to run here anymore; only the per-package pnpmDeps hashes below.
#
# Requires: nix (nix-command + flakes experimental features enabled),
# python3.

set -euo pipefail
cd "$(dirname "$0")"

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must be set}"

FLAKE="$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack"
SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
PKGS_ATTR="packages.$SYSTEM.pi-packages"

echo "==> Using flake: $FLAKE"
echo "==> System: $SYSTEM"

extract_hash() {
  grep -oP 'got:\s*\K\S+' | tail -n1
}

echo "==> Discovering packages under $PKGS_ATTR..."
mapfile -t packages < <(
  nix eval --json "$FLAKE#$PKGS_ATTR" --apply builtins.attrNames |
    python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)))'
)
if [ "${#packages[@]}" -eq 0 ]; then
  echo "No packages found under $FLAKE#$PKGS_ATTR -- check the flake path and output name." >&2
  exit 1
fi
echo "    found: ${packages[*]}"

for pkg in "${packages[@]}"; do
  echo "==> Resolving $pkg hash..."
  if ! out=$(nix build "$FLAKE#$PKGS_ATTR.$pkg" --no-link 2>&1); then
    hash=$(printf '%s\n' "$out" | extract_hash)
    if [ -z "$hash" ]; then
      echo "Couldn't extract hash for $pkg from:" >&2
      printf '%s\n' "$out" >&2
      exit 1
    fi
    python3 - "$pkg" "$hash" <<'PY'
import re, sys
pkg, hash_value = sys.argv[1], sys.argv[2]
with open("hashes.nix") as f:
    content = f.read()
pattern = re.compile(r'(%s\s*=\s*")[^"]*(";)' % re.escape(pkg))
if pattern.search(content):
    content = pattern.sub(lambda m: m.group(1) + hash_value + m.group(2), content)
else:
    content = re.sub(r'(packages\s*=\s*\{)', r'\1\n    %s = "%s";' % (pkg, hash_value), content, count=1)
with open("hashes.nix", "w") as f:
    f.write(content)
PY
    echo "    $pkg -> $hash"
  else
    echo "    $pkg already OK"
  fi
done

echo "==> Done. hashes.nix updated."
