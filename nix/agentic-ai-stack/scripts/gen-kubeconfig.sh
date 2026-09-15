#!/usr/bin/env bash
# nix run .#gen-kubeconfig -- <dev-or-staging-context> [service-account-name] [namespace]
#
# Generates a dedicated, RBAC-scoped kubeconfig for the `pi` container
# (spec §6). NEVER points this at a production context — it operates
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
#     bound into a standalone kubeconfig at ./kube/agent-kubeconfig.yaml
#
# Deny-by-default at the RBAC layer is the real backstop (spec §6) —
# the permission-extension `deny` rules on kubectl apply/delete/exec
# (config/pi/permission-system.config.json) are defense in depth on
# top of this, not a substitute for it.
set -euo pipefail

CONTEXT="${1:?usage: gen-kubeconfig.sh <kube-context> [service-account-name] [namespace]}"
SA_NAME="${2:-pi-sandbox-agent}"
NAMESPACE="${3:-default}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/kube"
OUT_FILE="$OUT_DIR/agent-kubeconfig.yaml"

echo "==> Target context: $CONTEXT   namespace: $NAMESPACE   service account: $SA_NAME"
read -r -p "This must be a dev/staging context, never production. Continue? [y/N] " confirm
[ "$confirm" = "y" ] || { echo "aborted"; exit 1; }

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
  # requires them — this is a starting point (spec §11 acceptance
  # criteria assume a working stack, not a specific RBAC shape).
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
SERVER="$(kubectl --context "$CONTEXT" config view --raw -o jsonpath="{.clusters[?(@.name=='$(kubectl --context "$CONTEXT" config view -o jsonpath="{.contexts[?(@.name=='$CONTEXT')].context.cluster}")')].cluster.server}")"
CA_DATA="$(kubectl --context "$CONTEXT" config view --raw -o jsonpath="{.clusters[?(@.name=='$(kubectl --context "$CONTEXT" config view -o jsonpath="{.contexts[?(@.name=='$CONTEXT')].context.cluster}")')].cluster.certificate-authority-data}")"

cat > "$OUT_FILE" <<EOF
apiVersion: v1
kind: Config
current-context: ${SA_NAME}
clusters:
  - name: ${CONTEXT}
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
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

echo "==> Wrote $OUT_FILE (mounted read-only into the pi container by compose.yaml)."
echo "    Token expires in 1h — re-run this script to refresh it before a session that outlives that."
