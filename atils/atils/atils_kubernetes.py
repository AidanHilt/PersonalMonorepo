import argparse
import base64
import logging
import os
import shutil
import sys

from atils.common import config, yaml_utils
from atils.common.settings import settings
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
        help="Select a subcommand", dest="subparser_name"
    )

    # Options for managing kubernetes secrets. This is different from Vault secrets management
    secrets_parser = subparsers.add_parser(
        "secrets", help="Commands to manage kubernetes secrets"
    )

    secrets_parser.add_argument(
        "command", choices=["decode"], help="Which command to use to operate on secrets"
    )

    secrets_parser.add_argument(
        "secret_name", help="The name of the secret to operate on"
    )

    secrets_parser.add_argument(
        "-n", "--namespace", help="The namespace of the secret to operate on"
    )

    # Options for RKE cluster setup
    rke_parser = subparsers.add_parser(
        "rke-setup", help="Commands to manage the rke installation"
    )
    rke_parser.add_argument(
        "-f",
        "--force",
        help="force the recreation of a cluster, in cases where it's already running",
    )
    rke_parser.add_argument(
        "-rk",
        "--replace-kubeconfig-only",
        help="Only copy the kubeconfig, but do not create a new cluster",
        action="store_true",
        default=False,
    )
    rke_parser.add_argument(
        "cluster_name",
        help="the name of the cluster to set up. This should match an rke file",
    )

    istio_parser = subparsers.add_parser(
        "istio", help="Commands to manage or interact with istio"
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

    if arguments.subparser_name == "rke-setup":
        if vars(arguments).get("replace_kubeconfig"):
            merge_and_replace_kubeconfig(arguments.cluster_name)
        else:
            setup_rke_cluster(
                arguments.cluster_name,
            )
            merge_and_replace_kubeconfig(arguments.cluster_name)

    elif arguments.subparser_name == "secrets":
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
                ]
            )

            _clear_pods_for_istio_injection(
                [
                    "ingress-nginx",
                    "istio-system",
                    "kube-public",
                    "kube-system",
                    "local-path-storage",
                ]
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
                "namespace", "default"
            )

        # Get the Secret from the specified namespace
        secret = api.read_namespaced_secret(
            name=secret_name, namespace=secret_namespace
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
        logging.error(f"An error occurred: {e}")


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
    """
    Loads some kind of kubernetes configuration, either in-cluster or in kubeconfig,
    and returns true if it is able to. If it cannot, it will return false, and the main
    function is in charge of failing if it needs to

    Returns:
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
            "Could not find a kubeconfig. Any commands related to kubernetes have been disabled"
        )
        return False


def merge_and_replace_kubeconfig(cluster_name: str) -> None:
    """
    Merge a kubeconfig generated by rke with the system-wide kubeconfig. This is done by creating a backup of the
    system-wide kubeconfig, then merging the two kubeconfigs, and then replacing the system-wide kubeconfig with the
    merged kubeconfig. This is done to avoid conflicts with other kubeconfigs that may be present in the system-wide
    kubeconfig. This function is used to replace the system-wide kubeconfig with a kubeconfig generated by rke.
    Args:
        cluster_name (str): The name of the cluster. For now, the valid options are
        dev-laptop, dev-cluster, and prod-cluster. TODO Update this documentation to reflect our new naming
        convention:
        qa-cluster: The K3s cluster running on our laptop
        preprod-cluster: The RKE cluster made out of VMs we use for testing in a working environment
        prod-cluster: The RKE cluster made out of VMs used to run our actual services
    """
    shutil.copy(
        f"{settings.KUBECONFIG_LOCATION}/config",
        f"{settings.KUBECONFIG_LOCATION}/config.bak",
    )
    merged_kubeconfig = yaml_utils.merge_kubeconfigs(
        f"{settings.KUBECONFIG_LOCATION}/config",
        os.path.join(
            settings.SCRIPT_INSTALL_DIRECTORY,
            f"../kubernetes/rke/kube_config_{cluster_name}.yaml",
        ),
        # TODO This is still hard coded
        "kind-dev-laptop",
        "local",
        "kind-dev-laptop",
        "kube-admin-local",
        "kind-dev-laptop",
        "local",
    )

    with open(f"{settings.KUBECONFIG_LOCATION}/config", "w") as kfile:
        kfile.truncate(0)
        kfile.write(merged_kubeconfig)


def setup_rke_cluster(cluster_name: str, force: bool = False):
    """
    Set up an RKE whose specification is in kubernetes/rke/cluster_name.yaml. First attempts to check if the cluster is
    available TODO this doesn't work properly yet.
    Args:
        cluster_name (str): The name of the cluster. For now, the valid options are
        dev-laptop, dev-cluster, and prod-cluster. TODO Update this documentation to reflect our new naming
        convention:
        qa-cluster: The K3s cluster running on our laptop
        preprod-cluster: The RKE cluster made out of VMs we use for testing in a working environment
        prod-cluster: The RKE cluster made out of VMs used to run our actual services
        force (bool): If True, the cluster will be set up even if it is already running. If False, the cluster will
        not be set up if it is already running. Defaults to False.
    """
    cluster_availability = _check_cluster_availability()

    if cluster_availability and not (force):
        logging.error(
            "Cluster was reachable and --force was not used. If you wish to overwrite your cluster, use --force."
        )
        exit(0)
    elif not (cluster_availability) or force:
        # TODO Make this take config, and try to move these configuration files
        cluster_config_location: str = os.path.join(
            settings.SCRIPT_INSTALL_DIRECTORY, f"../kubernetes/rke/{cluster_name}.yaml"
        )
        if os.path.isfile(cluster_config_location):
            # TODO we should add our own error checking here, rather than relying on RKE's.
            os.system(f"rke up --config {cluster_config_location}")
            merge_and_replace_kubeconfig(cluster_name)
        else:
            logging.error(
                f"Could not find an rke file named {cluster_name}.yaml. Aborting"
            )
            exit(1)


def _check_cluster_availability() -> bool:
    """
    Checks if the cluster in the active context is available, by attempting to list nodes on a five second timeout
    Returns:
        true if the operation to list nodes succeeds, and false otherwise
    """
    try:
        contexts, active_context = k8s_config.list_kube_config_contexts()
        cluster_name: str = active_context["context"]["cluster"]
        logging.debug(f"Checking cluster availability for cluster: {cluster_name}")
        # Create a CoreV1Api instance
        api_instance = client.CoreV1Api()

        # Get the list of nodes in the cluster
        api_response = api_instance.list_node(timeout_seconds=5)

        # Check if the cluster is reachable
        if api_response:
            logging.info(f"Cluster '{cluster_name}' is reachable.")
            return True
        else:
            logging.info(f"Cluster '{cluster_name}' is not reachable.")
            return False
    except Exception as e:
        if "[Errno 64]" in e.args[0]:
            logging.error(
                "Cluster host is down. If you are trying to setup a new cluster, use the"
                + ' "rke-setup [cluster_name]" subcommand'
            )
            return False
        elif "Max retries execeeded with url:" in e.args[0]:
            logging.error(
                "Cluster host is unreachable. If you are trying to setup a new cluster, use the"
                + ' "rke-setup [cluster_name]" subcommand'
            )
            return False

        else:
            logging.error("We found a new kind of issue! This is a bug.")
            logging.error(e)
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
                    if "istio-proxy" in [
                        container.name for container in pod.spec.containers
                    ]:
                        print(
                            f"Skipping pod '{pod.metadata.name}' in namespace '{namespace_name}' (Istio sidecar already"
                            + " injected)."
                        )
                        continue

                    # Check if the pod has the annotation sidecar.istio.io/inject: "false"
                    if (
                        pod.metadata.annotations
                        and pod.metadata.annotations.get("sidecar.istio.io/inject")
                        == "false"
                    ):
                        print(
                            f"Skipping pod '{pod.metadata.name}' in namespace '{namespace_name}' (annotation"
                            + ' sidecar.istio.io/inject: "false").'
                        )
                        continue

                    # Delete the pod
                    api.delete_namespaced_pod(pod.metadata.name, namespace_name)
                    print(
                        f"Deleted pod '{pod.metadata.name}' in namespace '{namespace_name}' for Istio injection."
                    )

    except Exception as e:
        print(f"Error: {str(e)}")


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
        print(f"Error: {str(e)}")
