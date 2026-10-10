#!/bin/bash

set -euo pipefail

# @lib: printing-and-output
# @lib: args-and-help

SECRET_NAME="postgres-config-secret"
NAMESPACE="postgres"
USERNAME_KEY="username"
PASSWORD_KEY="password"
POSTGRES_ENDPOINT="postgres-cluster-rw.postgres.svc.cluster.local"
DATABASE="postgres"

args_description "Reads a secret from a Kubernetes cluster and launches a pod that connects using those credentials."
args_value "" "--secret-name" SECRET_NAME "NAME" "Name of the Kubernetes secret to retrieve"
args_value "" "--namespace" NAMESPACE "NAMESPACE" "Kubernetes namespace containing the secret"
args_value "" "--username-key" USERNAME_KEY "KEY" "Key in the secret containing the username"
args_value "" "--password-key" PASSWORD_KEY "KEY" "Key in the secret containing the password"
args_value "" "--postgres-endpoint" POSTGRES_ENDPOINT "URL" "PostgreSQL endpoint URL"
args_value "" "--database" DATABASE "NAME" "Database name to connect to"

args_parse "$@" || {
  rc=$?
  exit "$(args_rc "$rc")"
}

print_status "Reading secret ${SECRET_NAME} from namespace ${NAMESPACE}"

USERNAME=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath="{.data.${USERNAME_KEY}}" | base64 -d)
PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath="{.data.${PASSWORD_KEY}}" | base64 -d)

if [ -z "${USERNAME}" ] || [ -z "${PASSWORD}" ]; then
  print_error "Failed to retrieve credentials from secret"
  exit 1
fi

POD_NAME="psql-client-${RANDOM}"

print_status "Launching psql client pod: ${POD_NAME}"

kubectl run "${POD_NAME}" \
  -n "${NAMESPACE}" \
  --image=alpine/psql:latest \
  --restart=Never \
  --env="PGPASSWORD=${PASSWORD}" \
  --env="PGUSER=${USERNAME}" \
  --env="PGHOST=${POSTGRES_ENDPOINT}" \
  --env="PGDATABASE=${DATABASE}" \
  --command -- sleep infinity

print_status "Waiting for pod to be ready"
kubectl wait --for=condition=ready pod/"${POD_NAME}" -n "${NAMESPACE}" --timeout=60s

print_status "Connecting to database ${DATABASE} at ${POSTGRES_ENDPOINT}"

kubectl exec -it "${POD_NAME}" -n "${NAMESPACE}" -- \
  psql -h "${POSTGRES_ENDPOINT}" -U "${USERNAME}" -d "${DATABASE}" || export EXIT_CODE=$?
true

if [[ ! -v EXIT_CODE ]]; then
  export EXIT_CODE=0
fi

if [[ $EXIT_CODE != 0 ]]; then
  print_warning "Was not able to connect directly, dropping into a bash shell to allow manual retries"
  kubectl exec -it "${POD_NAME}" -n "${NAMESPACE}" -- sh || true
fi

print_status "Cleaning up pod ${POD_NAME}"
kubectl delete pod "${POD_NAME}" -n "${NAMESPACE}" --wait=false
