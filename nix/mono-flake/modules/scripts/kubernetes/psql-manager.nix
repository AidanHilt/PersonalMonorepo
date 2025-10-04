{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

psql-manager = pkgs.writeShellScriptBin "psql-manager" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

SECRET_NAME="postgres-config"
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
  --env="PGHOST=''${POSTGRES_ENDPOINT} \
  --env="PGDATABASE=''${DATABASE}" \
  --command -- sleep infinity

print_status "Waiting for pod to be ready"
kubectl wait --for=condition=ready pod/"''${POD_NAME}" -n "''${NAMESPACE}" --timeout=60s

print_status "Connecting to database ''${DATABASE} at ''${POSTGRES_ENDPOINT}"

kubectl exec -it "''${POD_NAME}" -n "''${NAMESPACE}" -- \
  psql -h "''${POSTGRES_ENDPOINT}" -U "''${USERNAME}" -d "''${DATABASE}" || export EXIT_CODE=$?; true

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