{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

psql-manager = pkgs.writeShellScriptBin "psql-manager" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

show_help() {
  print_status "Usage: $0 [OPTIONS]"
  print_status ""
  print_status "Reads a secret from a Kubernetes cluster and launches a pod that connects using those credentials."
  print_status ""
  print_status "OPTIONS:"
  print_status "  --secret-name NAME      Name of the Kubernetes secret to retrieve"
  print_status "  --namespace NAMESPACE   Kubernetes namespace containing the secret"
  print_status "  --username-key KEY      Key in the secret containing the username"
  print_status "  --password-key KEY      Key in the secret containing the password"
  print_status "  --postgres-endpoint URL PostgreSQL endpoint URL"
  print_status "  --database NAME         Database name to connect to"
  print_status "  --help                  Show this help message"
}

SECRET_NAME="postgres-config-secret"
NAMESPACE="postgres"
USERNAME_KEY="username"
PASSWORD_KEY="password"
POSTGRES_ENDPOINT="postgres-cluster-rw.postgres.svc.cluster.local"
DATABASE="postgres"

while [[ $# -gt 0 ]]; do
  case $1 in
    --secret-name)
      SECRET_NAME="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --username-key)
      USERNAME_KEY="$2"
      shift 2
      ;;
    --password-key)
      PASSWORD_KEY="$2"
      shift 2
      ;;
    --postgres-endpoint)
      POSTGRES_ENDPOINT="$2"
      shift 2
      ;;
    --database)
      DATABASE="$2"
      shift 2
      ;;
    --help)
      show_help
      exit
      ;;
    *)
      print_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

print_status "Reading secret ''${SECRET_NAME} from namespace ''${NAMESPACE}"

USERNAME=$(kubectl get secret "''${SECRET_NAME}" -n "''${NAMESPACE}" -o jsonpath="{.data.''${USERNAME_KEY}}" | base64 -d)
PASSWORD=$(kubectl get secret "''${SECRET_NAME}" -n "''${NAMESPACE}" -o jsonpath="{.data.''${PASSWORD_KEY}}" | base64 -d)

if [ -z "''${USERNAME}" ] || [ -z "''${PASSWORD}" ]; then
  print_error "Failed to retrieve credentials from secret"
  exit 1
fi

POD_NAME="psql-client-''${RANDOM}"

print_status "Launching psql client pod: ''${POD_NAME}"

kubectl run "''${POD_NAME}" \
  -n "''${NAMESPACE}" \
  --image=alpine/psql:latest \
  --restart=Never \
  --env="PGPASSWORD=''${PASSWORD}" \
  --env="PGUSER=''${USERNAME}" \
  --env="PGHOST=''${POSTGRES_ENDPOINT}" \
  --env="PGDATABASE=''${DATABASE}" \
  --command -- sleep infinity

print_status "Waiting for pod to be ready"
kubectl wait --for=condition=ready pod/"''${POD_NAME}" -n "''${NAMESPACE}" --timeout=60s

print_status "Connecting to database ''${DATABASE} at ''${POSTGRES_ENDPOINT}"

kubectl exec -it "''${POD_NAME}" -n "''${NAMESPACE}" -- \
  psql -h "''${POSTGRES_ENDPOINT}" -U "''${USERNAME}" -d "''${DATABASE}" || export EXIT_CODE=$?; true

if [[ ! -v EXIT_CODE ]]; then
  export EXIT_CODE=0
fi

if [[ $EXIT_CODE != 0 ]]; then
  print_warning "Was not able to connect directly, dropping into a bash shell to allow manual retries"
  kubectl exec -it "''${POD_NAME}" -n "''${NAMESPACE}" -- sh || true
fi

print_status "Cleaning up pod ''${POD_NAME}"
kubectl delete pod "''${POD_NAME}" -n "''${NAMESPACE}" --wait=false
'';
in

{
  environment.systemPackages = [
    psql-manager
  ];
}