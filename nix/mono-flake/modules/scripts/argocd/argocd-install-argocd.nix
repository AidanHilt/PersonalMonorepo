{ inputs, globals, pkgs, machine-config, lib, ...}:

let
printing-and-output = import ../lib/_printing-and-output.nix { inherit pkgs; };

argocd-install-argocd = pkgs.writeShellScriptBin "argocd-install-argocd" ''
#!/bin/bash

set -euo pipefail

source ${printing-and-output.printing-and-output}

# Check if helm is installed
check_helm() {
  if ! command -v helm &> /dev/null; then
    print_error "Helm is not installed. Please install Helm first."
    exit 1
  fi
  print_status "Helm is installed: $(helm version --short)"
}

# Check if kubectl is installed
check_kubectl() {
  if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
  fi
  print_status "kubectl is installed: $(kubectl version --client --short)"
}

# Check if ArgoCD helm repo is added, if not add it
check_and_add_repo() {
  local repo_name="argo"
  local repo_url="https://argoproj.github.io/argo-helm"

  print_status "Checking if ArgoCD Helm repository is added..."

  if helm repo list | grep -q "^''${repo_name}[[:space:]]"; then
    print_status "ArgoCD Helm repository is already added"
  else
    print_status "Adding ArgoCD Helm repository..."
    helm repo add "''${repo_name}" "''${repo_url}"
    if [ $? -eq 0 ]; then
      print_status "Successfully added ArgoCD Helm repository"
    else
      print_error "Failed to add ArgoCD Helm repository"
      exit 1
    fi
  fi

  # Update repo to get latest charts
  print_status "Updating Helm repositories..."
  helm repo update
}

# Install ArgoCD
install_argocd() {
  local namespace="argocd"
  local release_name="argocd"

  # Create namespace if it doesn't exist
  print_status "Creating namespace \"''${namespace}\" if it doesn't exist..."
  kubectl create namespace "''${namespace}" --dry-run=client -o yaml | kubectl apply -f -

  # Prepare helm install command
  local helm_cmd="helm upgrade --install ''${release_name} argo/argo-cd --namespace ''${namespace}"

  # Add version if ARGOCD_TARGET_VERSION is set
  if [[ -n "''${ARGOCD_TARGET_VERSION:-}" ]]; then
    print_status "Installing ArgoCD with version: ''${ARGOCD_TARGET_VERSION}"
    helm_cmd="''${helm_cmd} --version ''${ARGOCD_TARGET_VERSION}"
  else
    print_status "Installing ArgoCD with latest version (ARGOCD_TARGET_VERSION not set)"
  fi

  # Add common configurations
  helm_cmd="''${helm_cmd} --create-namespace --wait --timeout=600s"

  print_status "Executing: ''${helm_cmd}"

  # Execute the helm command
  if eval "''${helm_cmd}"; then
    print_status "ArgoCD installed successfully!"
  else
    print_error "Failed to install ArgoCD"
    exit 1
  fi
}

# Wait for ArgoCD to be ready
wait_for_argocd() {
  local namespace="argocd"

  print_status "Waiting for ArgoCD pods to be ready..."

  # Wait for all deployments to be ready
  kubectl wait --for=condition=available --timeout=600s deployment --all -n "''${namespace}"

  print_status "ArgoCD is ready!"
}

# Get ArgoCD admin password
get_admin_password() {
  local namespace="argocd"

  print_status "Retrieving ArgoCD admin password..."

  # Wait a bit for the secret to be created
  sleep 5

  if kubectl get secret argocd-initial-admin-secret -n "''${namespace}" &> /dev/null; then
    local admin_password
    admin_password=$(kubectl get secret argocd-initial-admin-secret -n "''${namespace}" -o jsonpath="{.data.password}" | base64 -d)

    echo ""
    print_status "ArgoCD Admin Credentials:"
    echo "  Username: admin"
    echo "  Password: ''${admin_password}"
    echo ""
    print_status "You can access ArgoCD by port-forwarding:"
    echo "  kubectl port-forward svc/argocd-server -n ''${namespace} 8080:443"
    echo "  Then visit: https://localhost:8080"
  else
    print_warn "ArgoCD admin secret not found. It might take a few moments to be created."
    print_status "You can retrieve it later with:"
    echo "  kubectl get secret argocd-initial-admin-secret -n ''${namespace} -o jsonpath='{.data.password}' | base64 -d"
  fi
}

# Main function
main() {
  print_status "Starting ArgoCD installation script..."

  # Check prerequisites
  check_helm
  check_kubectl

  # Check and add helm repo
  check_and_add_repo

  # Install ArgoCD
  install_argocd

  # Wait for ArgoCD to be ready
  wait_for_argocd

  # Get admin password
  get_admin_password

  print_status "ArgoCD installation completed successfully!"
}

main "$@"
'';
in

{
  environment.systemPackages = [
  argocd-install-argocd
  ];
}