#!/usr/bin/env bash
# gen-profile.sh -- composes a launch-ready nono work profile from the
# flake-owned static base (profiles/work.base.json) plus per-launch
# filesystem grants. Never calls `nono` itself (PLAN.md Phase 3: this
# script only produces the JSON `nono run --profile <out>` is later given).
#
# Usage:
#   gen-profile.sh --base <work.base.json> --out <file> \
#     --webhook-url <url> --workdir <path> \
#     [--add <path>]... [--clone <path>]... [--state-dir <path>] \
#     [--extra-closure-root <store-path>]... [--os linux|darwin]
#   gen-profile.sh --self-test
#
# What it does:
#   1. Substitutes the literal token __APPROVAL_WEBHOOK_URL__ (wherever it
#      appears in the base profile) with the value of --webhook-url.
#   2. On Linux (--os linux, or auto-detected via `uname -s`), computes the
#      Nix closure (`nix-store -qR`) of /run/current-system/sw plus every
#      --extra-closure-root, in the order given, deduping with an
#      order-preserving `awk '!seen[$0]++'` (never `sort -u`, which would
#      destroy closure ordering -- see PLAN.md section 3, spike S3.2's
#      harness-bug note) and merges the result into filesystem.read (never
#      filesystem.allow, and never the nono `nix_runtime` group).
#   3. On macOS (--os darwin), skips the closure merge entirely -- see the
#      TODO note below and in IMPLEMENTERS.md.
#   4. Adds read-write grants (filesystem.allow) for --workdir,
#      --state-dir, every --add, and every --clone.
#   5. Validates the result is well-formed JSON and writes it atomically
#      (temp file + `mv` within the same directory as --out).
#
# A closure lookup can be overridden (for testing, or to avoid depending on
# `nix-store` at all) by setting GEN_PROFILE_CLOSURE_CMD to the path of an
# executable that takes one argument (a closure root) and prints one store
# path per line to stdout; see --self-test for an example.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gen-profile.sh --base <work.base.json> --out <file> \
  --webhook-url <url> --workdir <path> \
  [--add <path>]... [--clone <path>]... [--state-dir <path>] \
  [--extra-closure-root <store-path>]... [--os linux|darwin]
       gen-profile.sh --self-test
EOF
}

BASE=""
OUT=""
WEBHOOK_URL=""
WORKDIR=""
STATE_DIR=""
OS_OVERRIDE=""
ADD_PATHS=()
CLONE_PATHS=()
EXTRA_CLOSURE_ROOTS=()
SELF_TEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --base)
    BASE="${2:?--base requires a path argument}"
    shift 2
    ;;
  --out)
    OUT="${2:?--out requires a path argument}"
    shift 2
    ;;
  --webhook-url)
    WEBHOOK_URL="${2:?--webhook-url requires a URL argument}"
    shift 2
    ;;
  --workdir)
    WORKDIR="${2:?--workdir requires a path argument}"
    shift 2
    ;;
  --state-dir)
    STATE_DIR="${2:?--state-dir requires a path argument}"
    shift 2
    ;;
  --add)
    ADD_PATHS+=("${2:?--add requires a path argument}")
    shift 2
    ;;
  --clone)
    CLONE_PATHS+=("${2:?--clone requires a path argument}")
    shift 2
    ;;
  --extra-closure-root)
    EXTRA_CLOSURE_ROOTS+=("${2:?--extra-closure-root requires a path argument}")
    shift 2
    ;;
  --os)
    OS_OVERRIDE="${2:?--os requires linux or darwin}"
    shift 2
    ;;
  --self-test)
    SELF_TEST=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "gen-profile.sh: unknown argument: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

# order_preserving_dedupe: reads store paths on stdin, prints each distinct
# path once, in first-seen order. Deliberately not `sort -u` -- closure
# ordering must survive (PLAN.md section 3, S3.2).
order_preserving_dedupe() {
  awk '!seen[$0]++'
}

# closure_of: prints the closure of $1, one store path per line. Delegates
# to GEN_PROFILE_CLOSURE_CMD if set (test seam), else `nix-store -qR`.
closure_of() {
  local root="$1"
  if [[ -n "${GEN_PROFILE_CLOSURE_CMD:-}" ]]; then
    "$GEN_PROFILE_CLOSURE_CMD" "$root"
  else
    nix-store -qR "$root"
  fi
}

# detect_os: prints "linux" or "darwin".
detect_os() {
  if [[ -n "$OS_OVERRIDE" ]]; then
    printf '%s\n' "$OS_OVERRIDE"
    return
  fi
  case "$(uname -s)" in
  Darwin) printf 'darwin\n' ;;
  *) printf 'linux\n' ;;
  esac
}

# build_profile: writes the composed profile to $1, given:
#   $2 = base profile path
#   $3 = webhook url
#   $4 = os (linux|darwin)
#   $5 = workdir
#   $6 = state dir (may be empty)
#   $7+ = closure roots (linux only), then a literal "--" separator, then
#         add paths, then a literal "--" separator, then clone paths
# This positional interface is only used internally (by main and
# self_test) so a literal "--" separator is acceptable here.
build_profile() {
  local out="$1" base="$2" webhook_url="$3" os="$4" workdir="$5" state_dir="$6"
  shift 6

  local closure_roots=() add_paths=() clone_paths=()
  local section=closure
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      if [[ "$section" == closure ]]; then
        section=add
      elif [[ "$section" == add ]]; then
        section=clone
      fi
      continue
    fi
    case "$section" in
    closure) closure_roots+=("$arg") ;;
    add) add_paths+=("$arg") ;;
    clone) clone_paths+=("$arg") ;;
    esac
  done

  if [[ ! -f "$base" ]]; then
    echo "gen-profile.sh: base profile not found: $base" >&2
    return 1
  fi

  local tmp_profile
  tmp_profile="$(mktemp)"

  # Step 1: substitute the webhook URL placeholder, everywhere it occurs.
  jq --arg url "$webhook_url" \
    'walk(if type == "string" then gsub("__APPROVAL_WEBHOOK_URL__"; $url) else . end)' \
    "$base" >"$tmp_profile"

  # Step 2/3: closure-derived read-only grants (Linux only).
  local reads_file
  reads_file="$(mktemp)"
  trap 'rm -f "${tmp_profile:-}" "${reads_file:-}" "${reads_file:-}.merged"; trap - RETURN' RETURN
  if [[ "$os" == "linux" ]]; then
    {
      closure_of "/run/current-system/sw" || true
      local croot
      for croot in "${closure_roots[@]}"; do
        closure_of "$croot" || true
      done
    } | order_preserving_dedupe >"$reads_file"
  fi

  # Step 4: read-write grants -- workdir, state dir, --add, --clone.
  local rw_paths=("$workdir")
  if [[ -n "$state_dir" ]]; then
    rw_paths+=("$state_dir")
  fi
  local p
  for p in "${add_paths[@]}"; do
    rw_paths+=("$p")
  done
  for p in "${clone_paths[@]}"; do
    rw_paths+=("$p")
  done
  local rw_json
  rw_json="$(printf '%s\n' "${rw_paths[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')"

  jq --rawfile reads "$reads_file" --argjson rw "$rw_json" '                                                                                                              
    .filesystem.read = ((.filesystem.read // []) + ($reads | split("\n") | map(select(length > 0)))) |                                                                    
    .filesystem.allow = ((.filesystem.allow // []) + $rw)                                                                                                                 
  ' "$tmp_profile" >"$reads_file.merged"

  # Step 5: validate and write atomically.
  if ! jq empty "$reads_file.merged" 2>/dev/null; then
    echo "gen-profile.sh: generated profile is not valid JSON" >&2
    rm -f "$reads_file.merged"
    return 1
  fi

  local out_dir out_tmp
  out_dir="$(dirname "$out")"
  mkdir -p "$out_dir"
  out_tmp="$(mktemp "$out_dir/.gen-profile.XXXXXX")"
  mv "$reads_file.merged" "$out_tmp"
  mv -f "$out_tmp" "$out"
}

self_test() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"; trap - RETURN' RETURN

  local base="$tmp_dir/base.json"
  cat >"$base" <<'EOF'
{
  "extends": "default",
  "network": {
    "approval_backends": {
      "dialog": { "type": "webhook", "url": "__APPROVAL_WEBHOOK_URL__" }
    }
  },
  "filesystem": { "allow": [], "read": [], "unix_socket": [] }
}
EOF

  local fake_closure="$tmp_dir/fake-closure.sh"
  cat >"$fake_closure" <<'EOF'
#!/usr/bin/env bash
# Fixture closure generator for gen-profile.sh --self-test: deliberately
# emits an out-of-order, duplicate-laden list so the dedupe step has
# something real to prove it preserves first-seen order.
case "$1" in
/run/current-system/sw)
  printf '/nix/store/aaa-base\n/nix/store/bbb-shared\n/nix/store/aaa-base\n'
  ;;
*)
  printf '/nix/store/bbb-shared\n/nix/store/ccc-extra\n'
  ;;
esac
EOF
  chmod +x "$fake_closure"

  local out="$tmp_dir/out.json"
  GEN_PROFILE_CLOSURE_CMD="$fake_closure" build_profile \
    "$out" "$base" "http://127.0.0.1:9999/tok" "linux" \
    "$tmp_dir/workdir" "" \
    "$tmp_dir/extra-root" -- -- >/dev/null

  local fail=0

  local url
  url="$(jq -r '.network.approval_backends.dialog.url' "$out")"
  if [[ "$url" != "http://127.0.0.1:9999/tok" ]]; then
    echo "self-test FAIL: webhook url not substituted: $url" >&2
    fail=1
  fi

  local reads
  reads="$(jq -c '.filesystem.read' "$out")"
  local expected='["/nix/store/aaa-base","/nix/store/bbb-shared","/nix/store/ccc-extra"]'
  if [[ "$reads" != "$expected" ]]; then
    echo "self-test FAIL: dedupe/order mismatch: got $reads want $expected" >&2
    fail=1
  fi

  local allow
  allow="$(jq -c '.filesystem.allow' "$out")"
  if [[ "$allow" != "[\"$tmp_dir/workdir\"]" ]]; then
    echo "self-test FAIL: workdir not granted read-write: $allow" >&2
    fail=1
  fi

  if [[ "$fail" -eq 0 ]]; then
    echo "self-test: PASS"
    return 0
  fi
  return 1
}

main() {
  if [[ "$SELF_TEST" -eq 1 ]]; then
    self_test
    exit $?
  fi

  if [[ -z "$BASE" || -z "$OUT" || -z "$WEBHOOK_URL" || -z "$WORKDIR" ]]; then
    echo "gen-profile.sh: --base, --out, --webhook-url, and --workdir are required" >&2
    usage >&2
    exit 1
  fi

  local os
  os="$(detect_os)"

  if [[ "$os" == "darwin" ]]; then
    # TODO(macOS native grants): PLAN.md section 6 flags macOS Seatbelt
    # rule-count limits for a closure-sized grant list as UNTESTED. Rather
    # than guess at a workable closure substitute, this script currently
    # adds no closure-derived grants at all on darwin -- see
    # IMPLEMENTERS.md's "Work profile (Phase 3)" UNVERIFIED list. Native
    # macOS grants beyond read-write for workdir/add/clone/state-dir are
    # not yet implemented.
    :
  fi

  local args=()
  local root
  for root in "${EXTRA_CLOSURE_ROOTS[@]}"; do
    args+=("$root")
  done
  args+=("--")
  local p
  for p in "${ADD_PATHS[@]}"; do
    args+=("$p")
  done
  args+=("--")
  for p in "${CLONE_PATHS[@]}"; do
    args+=("$p")
  done

  build_profile "$OUT" "$BASE" "$WEBHOOK_URL" "$os" "$WORKDIR" "$STATE_DIR" "${args[@]}"
  echo "gen-profile.sh: wrote $OUT"
}

main
