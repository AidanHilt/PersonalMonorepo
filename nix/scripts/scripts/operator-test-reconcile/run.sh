#!/bin/bash
#include printing-and-output
set -euo pipefail
shopt -s nullglob

show_help() {
  echo "Usage: $0 <operator-name> [OPTIONS]"
  echo ""
  echo "Watches \$PERSONAL_MONOREPO_LOCATION/kubernetes/operators/operators/<operator-name>/test"
  echo "for changes. On any change, reconciles that operator's test Function"
  echo "fixtures (test/fixtures/valid and test/fixtures/invalid under that"
  echo "directory) into a dev namespace: valid fixtures are applied (and"
  echo "pruned once no longer present), invalid fixtures are checked with a"
  echo "server-side dry run and must be rejected by the API server. Removes"
  echo "the applied fixtures from the namespace when the loop exits."
  echo ""
  echo "Does not install the operator itself; run operator-reconcile first"
  echo "so the operator's CRDs exist in the target cluster."
  echo ""
  echo "This script is operator-agnostic: it only reads whatever fixtures"
  echo "exist under the given operator's test/fixtures/ directory."
  echo ""
  echo "Building the fixture functions under test/functions/ with ko requires"
  echo "the current branch to already be pushed to --repo-url, since ko"
  echo "clones source.url at source.ref rather than using the local working"
  echo "tree."
  echo ""
  echo "ARGUMENTS:"
  echo "  <operator-name>             Name of the operator to test (required)"
  echo ""
  echo "OPTIONS:"
  echo "  --namespace <namespace>    Reconcile fixtures into this namespace instead of <operator>-dev"
  echo "  --cluster-name <name>      kind cluster to target, via the 'kind-<name>' kubectl context (default: qa-cluster)"
  echo "  --repo-url <url>           Git URL substituted into fixtures as \$FIXTURE_REPO_URL (default: https://github.com/AidanHilt/PersonalMonorepo)"
  echo "  --ref <ref>                Git ref substituted into fixtures as \$FIXTURE_REF (default: current branch of \$PERSONAL_MONOREPO_LOCATION)"
  echo "  --help, -h                 Show this help"
}

discover_gvks() {
  # Prints one unique "<apiVersion> <kind>" pair per line, read out of
  # every fixture file in the given directory. No kind/group is hardcoded
  # here, so this works for any operator's fixtures, not just miura's.
  local dir=$1
  local f
  for f in "$dir"/*; do
    [[ -f "$f" ]] || continue
    yq eval '[.apiVersion, .kind] | join(" ")' "$f"
  done | sort -u
}

wait_for_crds() {
  local api_version kind group crd_name
  while read -r api_version kind; do
    [[ -n "$api_version" && -n "$kind" ]] || continue
    group="${api_version%%/*}"

    crd_name=$("${KUBECTL[@]}" get crd -o json |
      jq -r --arg group "$group" --arg kind "$kind" \
        '.items[] | select(.spec.group == $group and .spec.names.kind == $kind) | .metadata.name' |
      head -n1)

    if [[ -z "$crd_name" ]]; then
      print_error "No CRD found for group=${group} kind=${kind}; is the operator installed?"
      return 1
    fi

    print_debug "Waiting for CRD ${crd_name} to be Established"
    if ! "${KUBECTL[@]}" wait --for=condition=Established "crd/${crd_name}" --timeout=120s; then
      print_error "CRD ${crd_name} did not become Established"
      return 1
    fi
  done < <(
    discover_gvks "${TEST_DIR}/fixtures/valid"
    discover_gvks "${TEST_DIR}/fixtures/invalid"
  )
}

apply_valid_fixtures() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local f base

  for f in "${TEST_DIR}/fixtures/valid"/*; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    if ! FIXTURE_REPO_URL="$REPO_URL" FIXTURE_REF="$REF" envsubst '$FIXTURE_REPO_URL $FIXTURE_REF' <"$f" |
      yq eval '.metadata.labels."operator-test-reconcile/managed" = "true"' - >"${tmp_dir}/${base}"; then
      rm -rf "$tmp_dir"
      print_error "Failed to render fixture ${base}"
      return 1
    fi
  done

  local allowlist_args=()
  local api_version kind
  while read -r api_version kind; do
    [[ -n "$api_version" && -n "$kind" ]] || continue
    allowlist_args+=(--prune-allowlist="${api_version}/${kind}")
  done < <(discover_gvks "${TEST_DIR}/fixtures/valid")

  if ! "${KUBECTL[@]}" apply --namespace "$NAMESPACE" \
    -l operator-test-reconcile/managed=true --prune "${allowlist_args[@]}" \
    -f "$tmp_dir"; then
    rm -rf "$tmp_dir"
    print_error "kubectl apply of valid fixtures failed"
    return 1
  fi

  rm -rf "$tmp_dir"
}

check_invalid_fixtures() {
  local f base
  local pass_count=0
  local fail_count=0

  for f in "${TEST_DIR}/fixtures/invalid"/*; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")
    if FIXTURE_REPO_URL="$REPO_URL" FIXTURE_REF="$REF" envsubst '$FIXTURE_REPO_URL $FIXTURE_REF' <"$f" |
      "${KUBECTL[@]}" apply --namespace "$NAMESPACE" --dry-run=server -f - >/dev/null 2>&1; then
      print_error "FAIL ${base}: accepted by the API server (expected rejection)"
      fail_count=$((fail_count + 1))
    else
      print_status "PASS ${base}: rejected by the API server"
      pass_count=$((pass_count + 1))
    fi
  done

  print_status "invalid fixtures: ${pass_count} passed, ${fail_count} failed"
  [[ "$fail_count" -eq 0 ]]
}

sync_test_fixtures() {
  local sync_operator_name=$1

  if ! "${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1; then
    print_debug "Creating namespace ${NAMESPACE}"
    "${KUBECTL[@]}" create namespace "$NAMESPACE"
  fi

  if ! wait_for_crds; then
    print_error "${sync_operator_name}'s CRDs are not Established; is it installed? (see operator-reconcile)"
    return 1
  fi

  if ! apply_valid_fixtures; then
    return 1
  fi

  if ! check_invalid_fixtures; then
    print_warning "one or more invalid fixtures were incorrectly accepted by the API server"
  fi

  print_status "${sync_operator_name} test fixtures reconciled in namespace ${NAMESPACE}"
}

cleanup() {
  local api_version kind
  while read -r api_version kind; do
    [[ -n "$kind" ]] || continue
    "${KUBECTL[@]}" delete "$kind" -l operator-test-reconcile/managed=true \
      --namespace "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
  done < <(discover_gvks "${TEST_DIR}/fixtures/valid")
  rm -rf "$STATE_DIR"
  print_status "Test loop stopped, fixtures removed from namespace ${NAMESPACE}"
}

NAMESPACE_OVERRIDE=""
CLUSTER_NAME="qa-cluster"
REPO_URL="https://github.com/AidanHilt/PersonalMonorepo"
REF_OVERRIDE=""
SYNC_MODE=false
STATE_DIR=""
OPERATOR_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --namespace)
    NAMESPACE_OVERRIDE=$2
    shift 2
    ;;
  --cluster-name)
    CLUSTER_NAME=$2
    shift 2
    ;;
  --repo-url)
    REPO_URL=$2
    shift 2
    ;;
  --ref)
    REF_OVERRIDE=$2
    shift 2
    ;;
  --state-dir)
    STATE_DIR=$2
    shift 2
    ;;
  --sync)
    SYNC_MODE=true
    shift
    ;;
  --help | -h)
    show_help
    exit 0
    ;;
  --*)
    print_error "Unknown option: $1"
    exit 1
    ;;
  *)
    if [[ -n "$OPERATOR_NAME" ]]; then
      print_error "Unexpected argument: $1 (operator-name already set to '${OPERATOR_NAME}')"
      exit 1
    fi
    OPERATOR_NAME=$1
    shift
    ;;
  esac
done

if [[ -z "$OPERATOR_NAME" ]]; then
  print_error "operator-name is required"
  show_help
  exit 1
fi

readonly CLUSTER_NAME
readonly REPO_URL
readonly SYNC_MODE

if [[ -z "${PERSONAL_MONOREPO_LOCATION:-}" ]]; then
  print_error "PERSONAL_MONOREPO_LOCATION is not set"
  exit 1
fi

readonly OPERATORS_DIR="${PERSONAL_MONOREPO_LOCATION}/kubernetes/operators/operators"
readonly OPERATOR_DIR="${OPERATORS_DIR}/${OPERATOR_NAME}"
readonly TEST_DIR="${OPERATOR_DIR}/test"

if [[ ! -f "${OPERATOR_DIR}/go.mod" ]]; then
  print_error "No operator named '${OPERATOR_NAME}' found at ${OPERATOR_DIR}"
  exit 1
fi

if [[ ! -d "${TEST_DIR}/fixtures/valid" || ! -d "${TEST_DIR}/fixtures/invalid" ]]; then
  print_error "No test fixtures found at ${TEST_DIR}/fixtures/{valid,invalid}"
  exit 1
fi

if [[ -n "$NAMESPACE_OVERRIDE" ]]; then
  NAMESPACE=$NAMESPACE_OVERRIDE
else
  NAMESPACE="${OPERATOR_NAME}-dev"
fi
readonly NAMESPACE

if [[ -n "$REF_OVERRIDE" ]]; then
  REF=$REF_OVERRIDE
else
  REF=$(git -C "$PERSONAL_MONOREPO_LOCATION" rev-parse --abbrev-ref HEAD)
fi
readonly REF

readonly KUBECTL=(kubectl --context "kind-${CLUSTER_NAME}")

if [[ "$SYNC_MODE" == true ]]; then
  readonly STATE_DIR
  sync_test_fixtures "$OPERATOR_NAME" || print_warning "Skipping ${OPERATOR_NAME} this cycle"
  exit 0
fi

if [[ -z "$STATE_DIR" ]]; then
  STATE_DIR=$(mktemp -d)
fi
readonly STATE_DIR

trap cleanup EXIT INT TERM

print_debug "Watching ${TEST_DIR} for changes"
watchexec \
  --watch "$TEST_DIR" \
  -- "$0" "$OPERATOR_NAME" --sync --state-dir "$STATE_DIR" --namespace "$NAMESPACE" \
  --cluster-name "$CLUSTER_NAME" --repo-url "$REPO_URL" --ref "$REF"
