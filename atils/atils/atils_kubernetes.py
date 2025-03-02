import argparse
import base64
import logging
import os
import shutil
import sys

from atils.common import config
from kubernetes import client
from kubernetes import config as k8s_config

client.rest.logger.setLevel(logging.WARNING)

logging.basicConfig(level=config.get_logging_level())  # type: ignore


def main(args: list[str]):
  # This variable tracks whether or not we have configuration available to run kubernetes commands
  CAN_RUN: bool = load_config()

  if not CAN_RUN:
    logging.error("No configuration available to run kubernetes commands")
    exit(1)

  # TODO add autocomplete for secret names
  parser: argparse.ArgumentParser = argparse.ArgumentParser()
  subparsers = parser.add_subparsers(
    help="Select a subcommand",
    dest="subparser_name",
  )

  # Options for managing kubernetes secrets. This is different from Vault secrets management
  secrets_parser = subparsers.add_parser(
    "secrets",
    help="Commands to manage kubernetes secrets",
  )

  secrets_parser.add_argument(
    "command",
    choices=["decode"],
    help="Which command to use to operate on secrets",
  )

  secrets_parser.add_argument(
    "secret_name",
    help="The name of the secret to operate on",
  )

  secrets_parser.add_argument(
    "-n",
    "--namespace",
    help="The namespace of the secret to operate on",
  )

  istio_parser = subparsers.add_parser(
    "istio",
    help="Commands to manage or interact with istio",
  )
  istio_parser.add_argument(
    "command",
    choices=["label-namespaces"],
    help="Which istio-related operator to perform",
  )

  if len(args) == 0:
    parser.print_help(sys.stderr)
    sys.exit(1)

  arguments: argparse.Namespace = parser.parse_args(args)
  args_dict: dict[str, str] = vars(arguments)

  if arguments.subparser_name == "secrets":
    if args_dict["command"] == "decode":
      if args_dict["secret_name"] is None:
        logging.error("Error: A secret name must be provided ")
        sys.exit(1)
      else:
        get_and_decode_secret(args_dict["secret_name"], args_dict["namespace"])

  elif arguments.subparser_name == "istio":
    if args_dict["command"] == "label-namespaces":
      _label_namespaces_for_istio_injection(
        [
          "ingress-nginx",
          "istio-system",
          "kube-public",
          "kube-system",
          "local-path-storage",
        ],
      )

      _clear_pods_for_istio_injection(
        [
          "ingress-nginx",
          "istio-system",
          "kube-public",
          "kube-system",
          "local-path-storage",
        ],
      )


def check_namespace_exists(namespace_name: str) -> bool:
  """
  Check if a given kubernetes namespace exists
  Args:
    namespace_name (str): The name of the namespace to check
  Returns:
    bool: True if the namespace exists, False otherwise.
  """
  # Create Kubernetes API client
  v1 = client.CoreV1Api()

  # Use the API client to list all namespaces
  namespace_list = v1.list_namespace().items

  # Check if the namespace exists
  if any(namespace.metadata.name == namespace_name for namespace in namespace_list):
    return True
  else:
    return False


def get_and_decode_secret(secret_name: str, secret_namespace: str) -> None:
  """
  Get a kubernetes secret, and then decode and pretty print it
  Args:
    secret_name (str): The name of the secret to decode and print
    secret_namespace (str): The namespace the given secret is located in
  """
  try:
    # Create a Kubernetes API client
    api = client.CoreV1Api()

    if secret_namespace is None:
      current_context = k8s_config.list_kube_config_contexts()[1]
      # Check if current_context["context"]["namespace"] is None
      secret_namespace = current_context.get("context").get(
        "namespace",
        "default",
      )

    # Get the Secret from the specified namespace
    secret = api.read_namespaced_secret(
      name=secret_name,
      namespace=secret_namespace,
    )

    terminal_width = shutil.get_terminal_size().columns

    print("=" * int(terminal_width / 2))
    print(secret.metadata.name.center(int(terminal_width / 2)))
    print("=" * int(terminal_width / 2))

    # Decode and pretty print the data items
    for key, value in secret.data.items():
      decoded_value = base64.b64decode(value).decode("utf-8")
      # If decoded_value is more than one line, print on a new line
      if "\n" in decoded_value:
        print(f"{key}:")
        print(decoded_value)
      else:
        print(f"{key}: {decoded_value}")

      print("=" * int(terminal_width / 2))

  except Exception as e:
    logging.exception(f"An error occurred: {e}")


def get_current_namespace() -> str:
  """
  Gets the current namespace set in the current context
  Returns:
    str: The current namespace set in the current context
  """
  contexts, active_context = k8s_config.list_kube_config_contexts()

  if "namespace" in active_context["context"].keys():
    return active_context["context"]["namespace"]
  else:
    return "default"


def load_config() -> bool:
  """Loads some kind of kubernetes configuration, either in-cluster or in kubeconfig,
  and returns true if it is able to. If it cannot, it will return false, and the main
  function is in charge of failing if it needs to

  Returns
  -------
    (bool): True if a config could be loaded, false otherwise

  """
  # TODO also support running from a pod
  if "KUBECONFIG" in os.environ:
    k8s_config.load_kube_config(os.environ["KUBECONFIG"])
    return True
  # Check if ~/.kube/config exists
  if os.path.exists(os.path.expanduser("~/.kube/config")):
    k8s_config.load_kube_config()
    return True
  else:
    logging.info(
      "Could not find a kubeconfig. Any commands related to kubernetes have been disabled",
    )
    return False

def _clear_pods_for_istio_injection(excluded_namespaces: list[str]) -> None:
  try:
    # Create a Kubernetes API client
    api = client.CoreV1Api()

    # List all namespaces
    namespaces = api.list_namespace().items

    # Iterate over each namespace
    for namespace in namespaces:
      namespace_name = namespace.metadata.name

      # Check if the namespace is in the excluded list
      if namespace_name not in excluded_namespaces:
        # List all pods in the namespace
        pods = api.list_namespaced_pod(namespace_name).items

        # Iterate over each pod
        for pod in pods:
          # Check if the pod already has an Istio sidecar injected
          if "istio-proxy" in [container.name for container in pod.spec.containers]:
            print(
              f"Skipping pod '{pod.metadata.name}' in namespace '{namespace_name}' (Istio sidecar already"
              + " injected).",
            )
            continue

          # Check if the pod has the annotation sidecar.istio.io/inject: "false"
          if pod.metadata.annotations and pod.metadata.annotations.get("sidecar.istio.io/inject") == "false":
            print(
              f"Skipping pod '{pod.metadata.name}' in namespace '{namespace_name}' (annotation"
              + ' sidecar.istio.io/inject: "false").',
            )
            continue

          # Delete the pod
          api.delete_namespaced_pod(pod.metadata.name, namespace_name)
          print(
            f"Deleted pod '{pod.metadata.name}' in namespace '{namespace_name}' for Istio injection.",
          )

  except Exception as e:
    print(f"Error: {e!s}")


def _label_namespaces_for_istio_injection(excluded_namespaces: list[str]) -> None:
  try:
    # Create a Kubernetes API client
    api = client.CoreV1Api()

    # List all namespaces
    namespaces = api.list_namespace().items

    # Iterate over each namespace
    for namespace in namespaces:
      namespace_name = namespace.metadata.name

      # Check if the namespace is in the excluded list
      if namespace_name not in excluded_namespaces:
        # Add or update the Istio injection label
        labels = namespace.metadata.labels or {}
        labels["istio-injection"] = "enabled"
        namespace.metadata.labels = labels

        # Update the namespace
        api.patch_namespace(namespace_name, namespace)
        print(f"Labeled namespace '{namespace_name}' for Istio injection.")
      else:
        print(f"Skipping namespace '{namespace_name}' (excluded).")

  except Exception as e:
    print(f"Error: {e!s}")
