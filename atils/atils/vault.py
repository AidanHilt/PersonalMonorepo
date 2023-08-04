import hvac
import logging

from hvac.api.auth_methods import Kubernetes

# TODO make it so that logging is set up using config stored in config.py
logging.basicConfig(level=logging.DEBUG)


def setup_client() -> hvac.Client:
    client = hvac.Client("http://vault.dev.local/")
    if client.is_authenticated:
        return client
    else:
        logging.error("Failed to authenticate with Vault")
        exit(1)


def setup_kubernetes_auth():
    client = setup_client()

    auth_methods = client.sys.list_auth_methods()

    if "kubernetes/" not in auth_methods["data"].keys():
        client.sys.enable_auth_method(
            method_type="kubernetes",
            path="kubernetes",
        )

    Kubernetes(client.adapter).create_role("argocd", ["argocd-repo-server"], ["argocd"])


setup_kubernetes_auth()
