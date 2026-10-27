#!/usr/bin/env bash
# nix run .#gen-kubeconfig -- [FLAGS] <dev-or-staging-context> [service-account-name] [namespace]
#
# Generates a dedicated, RBAC-scoped kubeconfig for the `pi` container.
# NEVER points this at a production context — it operates
# against whatever context you pass in, so double check `kubectl config
# get-contexts` first and pass a dev/staging one explicitly.
#
# This creates:
#   - a ServiceAccount in the target namespace
#   - a Role with a minimal, explicit verb/resource allowlist (edit as
#     needed for the actual operator work in question — start narrow
#     and widen deliberately, not the other way around)
#   - a RoleBinding
#   - a short-lived (1h, auto-renew by re-running this script) token
#     bound into a standalone kubeconfig at $PI_SANDBOX__KUBECONFIG_PATH
#     (default: ~/.config/pi-sandbox/agent-kubeconfig.yaml), same default
#     path start-agent.sh / compose.kube.yaml look for it at.
#
# Deny-by-default at the RBAC layer is the real backstop — the
# permission-extension `deny` rules on kubectl apply/delete/exec
# (config/agent/permission-system.config.json) are defense in depth on
# top of this, not a substitute for it.
#
# Flags (may appear anywhere among the arguments, before/after/between the
# positional ones):
#   --yes, -y                 Skip the "must be dev/staging" y/N prompt.
#   --server <url>            Override the generated kubeconfig's cluster
#                              `server:` field instead of the target
#                              context's own API server address (e.g. when
#                              `pi` reaches the cluster through a network
#                              intermediary such as a forwarder sidecar
#                              rather than directly).
#   --tls-server-name <name>  Emit `tls-server-name: <name>` under the
#                              generated kubeconfig's cluster entry (e.g.
#                              a SAN on the target API server's cert, when
#                              --server doesn't match a name the cert was
#                              issued for).
#
# Positional arguments (in order, after flags are stripped):
#   <kube-context>             required
#   [service-account-name]     default: pi-sandbox-agent
#   [namespace]                default: default
set -euo pipefail

YES_FLAG=0
SERVER_OVERRIDE=""
TLS_SERVER_NAME=""
POSITIONAL=()

while [ $# -gt 0 ]; do
  case "$1" in
  --yes | -y)
    YES_FLAG=1
    shift
    ;;
  --server)
    shift
    SERVER_OVERRIDE="${1:?--server requires a URL argument}"
    shift
    ;;
  --server=*)
    SERVER_OVERRIDE="${1#--server=}"
    shift
    ;;
  --tls-server-name)
    shift
    TLS_SERVER_NAME="${1:?--tls-server-name requires a NAME argument}"
    shift
    ;;
  --tls-server-name=*)
    TLS_SERVER_NAME="${1#--tls-server-name=}"
    shift
    ;;
  --)
    shift
    while [ $# -gt 0 ]; do
      POSITIONAL+=("$1")
      shift
    done
    ;;
  -*)
    echo "error: unrecognized flag: $1" >&2
    exit 1
    ;;
  *)
    POSITIONAL+=("$1")
    shift
    ;;
  esac
done

CONTEXT="${POSITIONAL[0]:?usage: gen-kubeconfig.sh [FLAGS] <kube-context> [service-account-name] [namespace]}"
SA_NAME="${POSITIONAL[1]:-pi-sandbox-agent}"
NAMESPACE="${POSITIONAL[2]:-default}"
OUT_FILE="${PI_SANDBOX__KUBECONFIG_PATH:-$HOME/.config/pi-sandbox/agent-kubeconfig.yaml}"
OUT_DIR="$(dirname "$OUT_FILE")"

echo "==> Target context: $CONTEXT   namespace: $NAMESPACE   service account: $SA_NAME"
if [ "$YES_FLAG" = "1" ]; then
  echo "==> --yes/-y given, skipping the dev/staging confirmation prompt."
else
  read -r -p "This must be a dev/staging context, never production. Continue? [y/N] " confirm
  [ "$confirm" = "y" ] || {
    echo "aborted"
    exit 1
  }
fi

mkdir -p "$OUT_DIR"

kubectl --context "$CONTEXT" -n "$NAMESPACE" create serviceaccount "$SA_NAME" \
  --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -

cat <<EOF | kubectl --context "$CONTEXT" apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${SA_NAME}-role
  namespace: ${NAMESPACE}
rules:
  # Start narrow. Add verbs/resources deliberately as the operator work
  # requires them — this is a starting point (the acceptance criteria in
  # scripts/verify-acceptance.sh assume a working stack, not a specific
  # RBAC shape).
  - apiGroups: [""]
    resources: ["pods", "pods/log", "services", "configmaps", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch"]
EOF

cat <<EOF | kubectl --context "$CONTEXT" apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${SA_NAME}-binding
  namespace: ${NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: ${SA_NAME}-role
  apiGroup: rbac.authorization.k8s.io
EOF

echo "==> Minting a short-lived token (1h) and building a standalone kubeconfig..."
TOKEN="$(kubectl --context "$CONTEXT" -n "$NAMESPACE" create token "$SA_NAME" --duration=1h)"
if [ -n "$SERVER_OVERRIDE" ]; then
  echo "==> --server override given: $SERVER_OVERRIDE (ignoring the context's own API server address)"
  SERVER="$SERVER_OVERRIDE"
else
  SERVER="$(kubectl --context "$CONTEXT" config view --raw -o jsonpath="{.clusters[?(@.name=='$(kubectl --context "$CONTEXT" config view -o jsonpath="{.contexts[?(@.name=='$CONTEXT')].context.cluster}")')].cluster.server}")"
fi
CA_DATA="$(kubectl --context "$CONTEXT" config view --raw -o jsonpath="{.clusters[?(@.name=='$(kubectl --context "$CONTEXT" config view -o jsonpath="{.contexts[?(@.name=='$CONTEXT')].context.cluster}")')].cluster.certificate-authority-data}")"

TLS_SERVER_NAME_LINE=""
if [ -n "$TLS_SERVER_NAME" ]; then
  echo "==> --tls-server-name override given: $TLS_SERVER_NAME"
  TLS_SERVER_NAME_LINE="      tls-server-name: ${TLS_SERVER_NAME}"
fi

cat >"$OUT_FILE" <<EOF
apiVersion: v1
kind: Config
current-context: ${SA_NAME}
clusters:
  - name: ${CONTEXT}
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
${TLS_SERVER_NAME_LINE}
contexts:
  - name: ${SA_NAME}
    context:
      cluster: ${CONTEXT}
      namespace: ${NAMESPACE}
      user: ${SA_NAME}
users:
  - name: ${SA_NAME}
    user:
      token: ${TOKEN}
EOF
chmod 600 "$OUT_FILE"

echo "==> Wrote $OUT_FILE, overwriting any previous contents (mounted read-only into the pi container by compose.yaml)."
echo "    Token expires in 1h — re-run this script to refresh it before a session that outlives that."
