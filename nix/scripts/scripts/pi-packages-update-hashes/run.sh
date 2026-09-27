#!/usr/bin/env bash

cd "$(dirname "$0")" || exit

: "${PERSONAL_MONOREPO_LOCATION:?PERSONAL_MONOREPO_LOCATION must be set (path to your personal monorepo checkout)}"

FLAKE="$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack"
HASHES_FILE="$PERSONAL_MONOREPO_LOCATION/nix/agentic-ai-stack/hashes.nix"
SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
PKGS_ATTR="packages.$SYSTEM.pi-packages"

echo "==> Using flake: $FLAKE"
echo "==> System: $SYSTEM"

extract_hash() {
grep -o 'got:[[:space:]]*[^[:space:]]*' | tail -n1 | awk '{print $2}'
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

echo "==> Resolving shared pnpmDeps hash..."

echo "Huh"

echo "$FLAKE#$PKGS_ATTR.${packages[0]}"

echo "Oh"

if ! out=$(nix build "$FLAKE#$PKGS_ATTR.${packages[0]}" --no-link 2>&1); then
hash=$(printf '%s\n' "$out" | extract_hash)

if [ -z "$hash" ]; then
echo "Couldn't extract pnpmDeps hash from:" >&2
printf '%s\n' "$out" >&2
exit 1
fi

echo "WTF"

python3 - "$hash" "$HASHES_FILE" <<'PY'
import re
import sys

hash_value, hash_file_location = sys.argv[1], sys.argv[2]

with open(hash_file_location) as f:
    content = f.read()

pattern = re.compile(r'(pnpmDeps\s*=\s*")[^"]*(";?)')

if pattern.search(content):
    content = pattern.sub(
        lambda m: m.group(1) + hash_value + m.group(2),
        content,
        count=1,
    )
else:
    content = re.sub(
        r'(\{\s*)',
        r'\1\n  pnpmDeps = "%s";' % hash_value,
        content,
        count=1,
    )

with open(hash_file_location, "w") as f:
    f.write(content)
PY

echo "    pnpmDeps -> $hash"
else
echo "    pnpmDeps already OK"
fi

echo "==> Resolving per-package pnpmDeps hashes..."

for pkg in "${packages[@]}"; do
echo "    -- $pkg"

if ! out=$(nix build "$FLAKE#$PKGS_ATTR.$pkg" --no-link 2>&1); then
hash=$(printf '%s\n' "$out" | extract_hash)

if [ -z "$hash" ]; then
echo "Couldn't extract hash for package '$pkg' from:" >&2
printf '%s\n' "$out" >&2
exit 1
fi

python3 - "$pkg" "$hash" "$HASHES_FILE" <<'PY'
import re
import sys

pkg, hash_value, hash_file_location = sys.argv[1], sys.argv[2], sys.argv[3]

with open(hash_file_location) as f:
    content = f.read()

# Match an existing (possibly commented-out) entry for this package
# inside the `packages = { ... };` attrset, e.g.:
#   pi-nocd = "sha256-...";
#   # pi-subagents = "sha256-...";
entry_pattern = re.compile(
    r'(^[ \t]*#?[ \t]*' + re.escape(pkg) + r'\s*=\s*")[^"]*(";?[ \t]*$)',
    re.MULTILINE,
)

if entry_pattern.search(content):
    content = entry_pattern.sub(
        lambda m: m.group(1) + hash_value + m.group(2),
        content,
        count=1,
    )
else:
    # No existing entry -- insert a fresh one right after `packages = {`
    packages_block = re.compile(r'(packages\s*=\s*\{\s*)')
    if packages_block.search(content):
        content = packages_block.sub(
            r'\1\n  %s = "%s";' % (pkg, hash_value),
            content,
            count=1,
        )
    else:
        raise SystemExit(
            f"Couldn't find a `packages = {{ ... }}` attrset in {hash_file_location} "
            f"to insert entry for '{pkg}'."
        )

with open(hash_file_location, "w") as f:
    f.write(content)
PY

echo "       $pkg -> $hash"
else
echo "       $pkg already OK"
fi
done

echo "==> Done. hashes.nix updated."