{ lib, ... }:

{
  variable = {
    kubeconfig_location = {
      type        = "string";
      description = "Where the kubeconfig for our cluster is located";
      default     = "~/.kube/config";
    };

    kubeconfig_context = {
      type        = "string";
      description = "The Kubernetes context to run against";
    };
  };

  provider.kubernetes = {
    config_path    = "\${var.kubeconfig_location}";
    config_context = "\${var.kubeconfig_context}";
  };
}