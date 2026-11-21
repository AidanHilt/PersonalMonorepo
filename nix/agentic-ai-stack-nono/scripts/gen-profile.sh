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
#     [--read <path>]... [--os linux|darwin]
#   gen-profile.sh --self-test
#
# What it does:
#   1. Substitutes the literal token __APPROVAL_WEBHOOK_URL__ (wherever it
#      appears in the base profile) with the value of --webhook-url.
#   2. On Linux (--os linux, or auto-detected via `uname -s`), computes the
#      Nix closure (`nix-store -qR`) of /run/current-system/sw (always,
#      implicit) plus, for every --read path that is itself under
#      /nix/store, that path's own closure (falling back to granting just
#      that path if the closure lookup fails); --read paths OUTSIDE
#      /nix/store are never closure-expanded at all, just granted as-is.
#      Everything is merged, in order, with an order-preserving
#      `awk '!seen[$0]++'` dedupe (never `sort -u`, which would destroy
#      closure ordering -- see PLAN.md section 3, spike S3.2's harness-bug
#      note) into filesystem.read (never filesystem.allow, and never the
#      nono `nix_runtime` group).
#   3. On macOS (--os darwin), skips the closure merge entirely and grants
#      every --read path exactly as given -- see the TODO note below and
#      in IMPLEMENTERS.md.
#   4. Adds read-write grants (filesystem.allow) for --workdir,
#      --state-dir, every --add, and every --clone.
#   5. Appends every --read path that is NOT under /nix/store to the
#      fs_read array of every command_policies.commands[].from.session.
#      sandbox that already has one (store paths need not be -- those
#      sandboxes already grant /nix/store itself). Never creates an
#      fs_read array where one doesn't already exist.
#   6. Validates the result is well-formed JSON and writes it atomically
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
  [--read <path>]... [--os linux|darwin]
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
READ_PATHS=()
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
  --read)
    READ_PATHS+=("${2:?--read requires a path argument}")
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
    # shellcheck disable=SC2086 # intentionally unquoted: GEN_PROFILE_CLOSURE_CMD
    # may be a short command line (e.g. "bash /path/to/fixture.sh"), not
    # just a bare executable path -- --self-test relies on this so its
    # fixture script works even when it isn't itself marked executable
    # (e.g. a noexec tmpdir).
    $GEN_PROFILE_CLOSURE_CMD "$root"
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
#   $7+ = --read paths, then a literal "--" separator, then add paths,
#         then a literal "--" separator, then clone paths
# This positional interface is only used internally (by main and
# self_test) so a literal "--" separator is acceptable here.
build_profile() {
  local out="$1" base="$2" webhook_url="$3" os="$4" workdir="$5" state_dir="$6"
  shift 6

  local read_paths=() add_paths=() clone_paths=()
  local section=read
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--" ]]; then
      if [[ "$section" == read ]]; then
        section=add
      elif [[ "$section" == add ]]; then
        section=clone
      fi
      continue
    fi
    case "$section" in
    read) read_paths+=("$arg") ;;
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

  # Step 2/3: closure-derived + as-is read-only grants from --read.
  local reads_file
  reads_file="$(mktemp)"
  local merged_file
  merged_file="$(mktemp)"
  local cp_file
  cp_file="$(mktemp)"
  trap 'rm -f "${tmp_profile:-}" "${reads_file:-}" "${merged_file:-}" "${cp_file:-}"; trap - RETURN' RETURN

  # process_read_arg: prints the grant(s) for one --read argument.
  #   - /nix/store/* paths: closure-expand via closure_of; on failure,
  #     fall back to granting just that path itself (today's behaviour
  #     silently swallowed closure failures with `|| true` and granted
  #     nothing at all for that root -- this now degrades to a narrower,
  #     but still-granted, single-path fallback instead).
  #   - any other path: granted as-is, no closure lookup at all.
  process_read_arg() {
    local rp="$1" closure_out
    if [[ "$rp" == /nix/store/* ]]; then
      if closure_out="$(closure_of "$rp" 2>/dev/null)"; then
        printf '%s\n' "$closure_out"
      else
        printf '%s\n' "$rp"
      fi
    else
      printf '%s\n' "$rp"
    fi
  }

  if [[ "$os" == "linux" ]]; then
    {
      closure_of "/run/current-system/sw" || true
      local rp
      for rp in "${read_paths[@]}"; do
        process_read_arg "$rp"
      done
    } | order_preserving_dedupe >"$reads_file"
  else
    # macOS: no closure merge at all (see the TODO in main()) -- every
    # --read path is granted exactly as given.
    {
      local rp
      for rp in "${read_paths[@]}"; do
        printf '%s\n' "$rp"
      done
    } | order_preserving_dedupe >"$reads_file"
  fi

  # Non-/nix/store --read paths also get layered into every
  # command_policies sandbox's fs_read array that already has one (store
  # paths need not be -- those sandboxes already grant /nix/store itself;
  # see profiles/work.base.json's "nix" command policy).
  local non_store_reads=()
  local rp
  for rp in "${read_paths[@]}"; do
    [[ "$rp" == /nix/store/* ]] || non_store_reads+=("$rp")
  done

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
  ' "$tmp_profile" >"$merged_file"

  # Step 5: non-/nix/store --read paths also land in every
  # command_policies sandbox's fs_read array that already has one. Never
  # creates an fs_read array (or a command_policies block) where one
  # doesn't already exist.
  local non_store_json
  non_store_json="$(printf '%s\n' "${non_store_reads[@]:-}" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  jq --argjson extra "$non_store_json" '
    if (($extra | length) > 0) and ((.command_policies.commands | type) == "object") then
      .command_policies.commands |= with_entries(
        (try (.value.from.session.sandbox.fs_read) catch null) as $fsread |
        if ($fsread | type) == "array" then
          .value.from.session.sandbox.fs_read = ($fsread + $extra)
        else . end
      )
    else . end
  ' "$merged_file" >"$cp_file"

  # Step 6: validate and write atomically.
  if ! jq empty "$cp_file" 2>/dev/null; then
    echo "gen-profile.sh: generated profile is not valid JSON" >&2
    return 1
  fi

  local out_dir out_tmp
  out_dir="$(dirname "$out")"
  mkdir -p "$out_dir"
  out_tmp="$(mktemp "$out_dir/.gen-profile.XXXXXX")"
  mv "$cp_file" "$out_tmp"
  mv -f "$out_tmp" "$out"
}

self_test() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"; trap - RETURN' RETURN

  # Base fixture includes a command_policies block (mirroring
  # profiles/work.base.json's "nix" command) so the non-/nix/store --read
  # -> fs_read append path has something real to exercise, plus a
  # deny-only command (a bare "deny" string, like "update"/
  # "nixos-rebuild") to prove that shape is left untouched.
  local base="$tmp_dir/base.json"
  cat >"$base" <<'EOF'
{
  "extends": "default",
  "network": {
    "approval_backends": {
      "dialog": { "type": "webhook", "url": "__APPROVAL_WEBHOOK_URL__" }
    }
  },
  "filesystem": { "allow": [], "read": [], "unix_socket": [] },
  "command_policies": {
    "commands": {
      "update": { "from": { "session": "deny" } },
      "nix": {
        "from": {
          "session": {
            "sandbox": {
              "fs_read": ["/nix/store", "/nix/var/nix"]
            }
          }
        }
      }
    }
  }
}
EOF

  # Fixture closure generator:
  #   - /run/current-system/sw: deliberately out-of-order and
  #     duplicate-laden, so the dedupe step has something real to prove
  #     it preserves first-seen order.
  #   - /nix/store/good-closure-root: a --read store path whose closure
  #     lookup succeeds.
  #   - /nix/store/bad-closure-root: a --read store path whose closure
  #     lookup deliberately fails, to exercise the fallback-to-itself
  #     path.
  #   - anything else (in particular a non-/nix/store --read path, which
  #     should never even reach this script): a sentinel value, so that
  #     if a non-store --read path were ever wrongly closure-looked-up,
  #     the sentinel would leak into filesystem.read and fail this
  #     self-test's assertions below.
  # Note: invoked as "bash $fake_closure" (via GEN_PROFILE_CLOSURE_CMD, see
  # closure_of's own comment above) rather than relying on its own +x bit
  # -- this self-test must also work under a noexec tmpdir.
  local fake_closure="$tmp_dir/fake-closure.sh"
  cat >"$fake_closure" <<'EOF'
#!/usr/bin/env bash
case "$1" in
/run/current-system/sw)
  printf '/nix/store/aaa-base\n/nix/store/bbb-shared\n/nix/store/aaa-base\n'
  ;;
/nix/store/good-closure-root)
  printf '/nix/store/bbb-shared\n/nix/store/ccc-extra\n'
  ;;
/nix/store/bad-closure-root)
  exit 1
  ;;
*)
  printf '/UNEXPECTED-CLOSURE-CALL\n'
  ;;
esac
EOF
  chmod +x "$fake_closure" 2>/dev/null || true

  local fail=0

  # --- Linux build: store-path closure expansion, closure-failure
  # fallback, non-store as-is grant, and command_policies fs_read append.
  local out_linux="$tmp_dir/out-linux.json"
  GEN_PROFILE_CLOSURE_CMD="bash $fake_closure" build_profile \
    "$out_linux" "$base" "http://127.0.0.1:9999/tok" "linux" \
    "$tmp_dir/workdir" "" \
    "/nix/store/good-closure-root" "/nix/store/bad-closure-root" "$tmp_dir/plain-read" -- -- >/dev/null

  local url
  url="$(jq -r '.network.approval_backends.dialog.url' "$out_linux")"
  if [[ "$url" != "http://127.0.0.1:9999/tok" ]]; then
    echo "self-test FAIL: webhook url not substituted: $url" >&2
    fail=1
  fi

  local reads
  reads="$(jq -c '.filesystem.read' "$out_linux")"
  local expected_reads="[\"/nix/store/aaa-base\",\"/nix/store/bbb-shared\",\"/nix/store/ccc-extra\",\"/nix/store/bad-closure-root\",\"$tmp_dir/plain-read\"]"
  if [[ "$reads" != "$expected_reads" ]]; then
    echo "self-test FAIL: linux filesystem.read mismatch: got $reads want $expected_reads" >&2
    fail=1
  fi

  local allow
  allow="$(jq -c '.filesystem.allow' "$out_linux")"
  if [[ "$allow" != "[\"$tmp_dir/workdir\"]" ]]; then
    echo "self-test FAIL: workdir not granted read-write: $allow" >&2
    fail=1
  fi

  local nix_fs_read
  nix_fs_read="$(jq -c '.command_policies.commands.nix.from.session.sandbox.fs_read' "$out_linux")"
  local expected_nix_fs_read="[\"/nix/store\",\"/nix/var/nix\",\"$tmp_dir/plain-read\"]"
  if [[ "$nix_fs_read" != "$expected_nix_fs_read" ]]; then
    echo "self-test FAIL: nix command_policies fs_read mismatch: got $nix_fs_read want $expected_nix_fs_read" >&2
    fail=1
  fi

  local update_policy
  update_policy="$(jq -c '.command_policies.commands.update' "$out_linux")"
  if [[ "$update_policy" != '{"from":{"session":"deny"}}' ]]; then
    echo "self-test FAIL: deny-only command_policies entry was mutated: $update_policy" >&2
    fail=1
  fi

  # --- Darwin build: no closure merge at all -- every --read path
  # (store or not) is granted exactly as given, in order.
  local out_darwin="$tmp_dir/out-darwin.json"
  GEN_PROFILE_CLOSURE_CMD="bash $fake_closure" build_profile \
    "$out_darwin" "$base" "http://127.0.0.1:9999/tok" "darwin" \
    "$tmp_dir/workdir" "" \
    "/nix/store/good-closure-root" "$tmp_dir/plain-read2" -- -- >/dev/null

  local reads_darwin
  reads_darwin="$(jq -c '.filesystem.read' "$out_darwin")"
  local expected_reads_darwin="[\"/nix/store/good-closure-root\",\"$tmp_dir/plain-read2\"]"
  if [[ "$reads_darwin" != "$expected_reads_darwin" ]]; then
    echo "self-test FAIL: darwin filesystem.read mismatch: got $reads_darwin want $expected_reads_darwin" >&2
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
    # adds no closure-derived grants at all on darwin -- every --read path
    # is granted exactly as given instead -- see IMPLEMENTERS.md's "Work
    # profile (Phase 3)" UNVERIFIED list. Native macOS grants beyond
    # read-write for workdir/add/clone/state-dir are not yet implemented.
    :
  fi

  local args=()
  local rp
  for rp in "${READ_PATHS[@]}"; do
    args+=("$rp")
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
