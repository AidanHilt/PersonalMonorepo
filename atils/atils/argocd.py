import argparse
import itertools
import json
import logging
import subprocess
import sys
import time
import webbrowser

import colored
import requests
import yaml

from atils import atils_kubernetes as k8s_utils
from atils.common import config, template_utils
from atils.common.settings import settings
from kubernetes import client

client.rest.logger.setLevel(logging.WARNING)

logging.basicConfig(level=config.get_logging_level())  # type: ignore


def main(args: list[str]) -> None:
    # This variable tracks whether or not we have configuration available to run kubernetes commands
    CAN_RUN: bool = k8s_utils.load_config()

    if not CAN_RUN:
        logging.error("No configuration available to run kubernetes commands")
        exit(1)

    # TODO Add auto-complete for application names
    # TODO Add a command to list all apps and their status
    parser: argparse.ArgumentParser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(
        help="Commands to manage argocd", dest="subparser_name"
    )

    setup_parser = subparsers.add_parser(
        "full-setup", help="Install ArgoCD, and install the master-stack application"
    )
    setup_parser.add_argument(
        "environment",
        choices=["qa-cluster", "preprod-cluster", "prod-cluster"],
        help="Which environment to use for templating",
    )
    setup_parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Force installation even if already installed",
    )
    setup_parser.add_argument(
        "--git-revision",
        "-gr",
        help="The revision to target for master-stack",
        default="master",
    )
    setup_parser.add_argument(
        "--configuration-repo",
        "-crp",
        help="The repository where the configuration for master-stack is stored",
        default="https://github.com/AidanHilt/PersonalMonorepo",
    )
    setup_parser.add_argument(
        "--configuration-directory",
        "-cd",
        help="The directory in the configuration repo where the master-stack config lives",
        default="kubernetes/argocd/configuration-data",
    )

    master_stack_parser = subparsers.add_parser(
        "install-master-stack",
        help="Install the master-stack application, configured for the environment",
    )
    master_stack_parser.add_argument(
        "environment",
        choices=["qa-cluster", "preprod-cluster", "prod-cluster"],
        help="Which environment to use for templating",
    )
    master_stack_parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Force installation even if already installed",
    )
    master_stack_parser.add_argument(
        "--git-revision",
        "-gr",
        help="The revision to target for master-stack",
        default="master",
    )
    master_stack_parser.add_argument(
        "--configuration-repo",
        "-crp",
        help="The repository where the configuration for master-stack is stored",
        default="https://github.com/AidanHilt/PersonalMonorepo",
    )
    master_stack_parser.add_argument(
        "--configuration-directory",
        "-cd",
        help="The directory in the configuration repo where the master-stack config lives",
        default="kubernetes/argocd/configuration-data",
    )

    install_argocd_parser = subparsers.add_parser(
        "install-argocd",
        help="Install argocd",
    )
    install_argocd_parser.add_argument(
        "environment",
        choices=["qa-cluster", "preprod-cluster", "prod-cluster"],
        help="Which environment to use for templating",
    )

    port_forward_parser = subparsers.add_parser(
        "port-forward",
        help="Automatically port fowards ArgoCD, opens a browser, and copies the password",
    )

    get_password_parser = subparsers.add_parser(
        "get-password", help="Get the admin password using the default secret."
    )

    disable_parser = subparsers.add_parser(
        "disable",
        help="Disables an application from the master stack",
    )
    disable_parser.add_argument("application", help="The application to disable")

    enable_parser = subparsers.add_parser(
        "enable",
        help="Ensables an application from the master stack",
    )
    enable_parser.add_argument("application", help="The application to enable")

    if len(args) == 0:
        parser.print_help(sys.stderr)
        sys.exit(1)

    arguments: argparse.Namespace = parser.parse_args(args)

    # Install ArgoCD, and then install the master-stack to get our setup up and running
    if arguments.subparser_name == "full-setup":
        args_dict = vars(arguments)
        setup_argocd(args_dict)
    # Install just the master-stack application
    elif arguments.subparser_name == "install-master-stack":
        args_dict = vars(arguments)
        install_master_stack(args_dict)
    # Only install ArgoCD
    elif arguments.subparser_name == "install-argocd":
        args_dict = vars(arguments)
        install_argocd(args_dict["environment"])
    # Port forward ArgoCD and open a browser window
    elif arguments.subparser_name == "port-forward":
        open_argocd_port_forward()
    # Disable an application from the master stack
    elif arguments.subparser_name == "disable":
        args_dict = vars(arguments)
        # Check if we provided an application argument, and disable it if we did
        if args_dict["application"] is None:
            logging.error("Please provide an application name")
            sys.exit(1)
        else:
            disable_application(args_dict["application"])
    # Enable an application from the master stack
    elif arguments.subparser_name == "enable":
        args_dict = vars(arguments)
        # Check if we provided an application argument, and enable it if we did
        if args_dict["application"] is None:
            logging.error("Please provide an application name")
            sys.exit(1)
        else:
            enable_application(args_dict["application"])
    # Get the ArgoCD password from the default secret
    # TODO once we've validated that ArgoCD doesn't do its own auth, delete this
    elif arguments.subparser_name == "get-password":
        get_argocd_password()
    else:
        logging.error(f"Invalid command: {arguments.subparser_name}")
        exit(1)


# Sync so that the app deletes when we run this
def disable_application(application: str) -> None:
    """
    Disable the specified application. It must be a sub-application of the master stack
    Args:
        application (str): The name of the application to disable
    """
    try:
        api_instance = client.CustomObjectsApi()
        api_response = _get_master_stack_application()

        resources = api_response.get("status").get("resources")  # type: ignore

        is_active = _is_application_active(application, resources)
        is_enabled = _is_application_enabled_in_master_stack(application, api_response)

        # Constants we'll use for modifying the master-stack later
        namespace = "argocd"
        name = "master-stack"
        group = "argoproj.io"
        version = "v1alpha1"
        plural = "applications"

        if not is_enabled:
            logging.info(f"Application {application} already disabled")
            exit(0)
        else:
            # Check Helm parameters for application
            source_helm_params = _get_source_helm_params(api_response)

            # Create a new helm parameter with the given application name and value
            new_helm_param = {"name": f"{application}.enabled", "value": "false"}
            edited_parameters = source_helm_params + [new_helm_param]

            # Create JSON merge patch to update the helm parameters
            json_patch = {
                "spec": {"source": {"helm": {"parameters": edited_parameters}}}
            }

            # Use patch_namespaced_custom_object to update the application with the new helm parameter
            api_response = api_instance.patch_namespaced_custom_object(
                group, version, namespace, plural, name, json_patch
            )

            logging.info(f"{application} disabled in master-stack")

            if is_active:
                api = client.CustomObjectsApi()

                try:
                    api.delete_namespaced_custom_object(
                        group="argoproj.io",
                        version="v1alpha1",
                        namespace="argocd",
                        plural="applications",
                        name=application,
                    )
                except Exception as e:
                    logging.error(
                        f"Unable to delete application {application}, although disabling was successful"
                    )
                    exit(1)

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def enable_application(application: str) -> None:
    """
    Enable the specified application. It must be a sub-application of the master stack
    Args:
        application (str): The name of the application to enable
    """
    try:
        api_instance = client.CustomObjectsApi()

        # Get the master-stack application, located in the ArgoCD namespace. This is what should be creating all of
        # our applications, so we want disable the target application in master-stacks parameters, so it doesn't
        # recreate it
        api_response: dict = _get_master_stack_application()

        resources = api_response.get("status").get("resources")  # type: ignore

        is_active = _is_application_active(application, resources)
        is_enabled = _is_application_enabled_in_master_stack(application, api_response)

        # Constants we'll use for modifying the master-stack later
        namespace = "argocd"
        name = "master-stack"
        group = "argoproj.io"
        version = "v1alpha1"
        plural = "applications"

        if is_enabled:
            logging.info(f"Application {application} already enabled")
            exit(0)
        else:
            # Get Helm parameters for application
            source_helm_params = _get_source_helm_params(api_response)

            edited_parameters = source_helm_params

            for i in range(len(edited_parameters)):
                if application == edited_parameters[i].get("name").split(".")[0]:  # type: ignore
                    del edited_parameters[i]

            # Create JSON merge patch to update the helm parameters
            json_patch = {
                "spec": {"source": {"helm": {"parameters": edited_parameters}}}
            }

            # Use patch_namespaced_custom_object to update the application with the new helm parameter
            api_response = api_instance.patch_namespaced_custom_object(
                group, version, namespace, plural, name, json_patch
            )

            logging.info(f"Application {application} enabled successfully")
            if not is_active:
                logging.debug(f"Syncing {application} so it actually shows up")
                sync_master_stack_application(application)
            else:
                logging.debug(f"No need to sync {application}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def get_argocd_password() -> None:
    # TODO once we've validated that ArgoCD doesn't do its own auth, delete this
    # Use kubectl to get the ArgoCD password
    result = subprocess.run(
        "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={{.data.password}} | base64 -d".format(),
        shell=True,
        capture_output=True,
    )
    subprocess.run(
        f"echo {result.stdout.decode('utf-8')} | pbcopy",
        shell=True,
        capture_output=True,
    )


def get_tracked_applications():
    """
    Get all applications under the master stack application. It loops over the resources field, picking out names
    whose kind is Application
    """
    api = client.CustomObjectsApi()

    master = api.get_namespaced_custom_object(
        group="argoproj.io",
        version="v1alpha1",
        name="master-stack",
        namespace="argocd",
        plural="applications",
    )

    resources = master["status"]["resources"]

    application_names = []
    for resource in resources:
        if resource["kind"] == "Application":
            application_names.append(resource["name"])

    return application_names


def install_argocd(environment: str) -> None:
    """
    Create the ArgoCD namespace if it doesn't exist, install ArgoCD with Helm (we don't check if its installed
    currently), then wait for the ArgoCD pods to be ready, then install the master stack
    Args:
        environment (str): The name of the environment we want to install into.
            qa-cluster: The kind cluster running on our laptop
            preprod-cluster: The RKE cluster made out of VMs we use for testing in a working environment
            prod-cluster: The RKE cluster made out of bare-metal instances used to run our actual services
    """
    # Check if the argocd namespace exists, and create it if it doesn't
    if not k8s_utils.check_namespace_exists("argocd"):
        api = client.CoreV1Api()

        # Create the namespace
        namespace_body = client.V1Namespace(metadata=client.V1ObjectMeta(name="argocd"))
        api.create_namespace(namespace_body)

    # Using the helm CLI as a dependency to add the argo repo, and install it.
    # TODO check if ArgoCD is already installed
    # TODO use environment-specific values files
    result = subprocess.run(
        f"""helm repo add argo https://argoproj.github.io/argo-helm && helm -n argocd upgrade --install argocd \
            -f {settings.SCRIPT_INSTALL_DIRECTORY}/../kubernetes/argocd/values.yaml argo/argo-cd""",
        shell=True,
        capture_output=True,
    )

    if result.returncode == 0:
        logging.info("ArgoCD Helm chart successfully installed")
    else:
        logging.warning(result.stdout)
        logging.warning("ArgoCD Helm chart failed to install. Exiting")
        exit(1)

    _wait_for_argocd_pods_to_be_ready()


def install_master_stack(args_dict: dict[str, str]) -> None:
    """
    Checks if an application named master-stack exists in the 'argocd' application, and if it doesn't,
    fill out the master-stack application template, and install it to the ArgoCD namespace. If the force
    argument is set to true, it will delete and recreate it
    Args:
        args_dict (dict[str, str]): The dictionary of arguments passed to the script
    """
    custom_objects_api = client.CustomObjectsApi()
    # Check whether an argocd application named 'master-stack' exists...
    try:
        custom_objects_api.get_namespaced_custom_object(
            group="argoproj.io",
            version="v1alpha1",
            namespace="argocd",
            plural="applications",
            name="master-stack",
        )

        # ... and if it does exist, but force is set to true, then recreate it. But, if it doesn't exist...
        if args_dict["force"]:
            logging.info("Forcing master-stack recreation")
            custom_objects_api.delete_namespaced_custom_object(
                group="argoproj.io",
                version="v1alpha1",
                namespace="argocd",
                plural="applications",
                name="master-stack",
            )
            _apply_master_stack_object(args_dict, custom_objects_api)
    # ...create it.
    except client.exceptions.ApiException as e:
        if e.status == 404:
            _apply_master_stack_object(args_dict, custom_objects_api)
        else:
            logging.info(
                "Master-stack already exists. If you want to force a recreation, use"
                + " --force-master-reconfiguration[Not yet working]"
            )


def open_argocd_port_forward():
    """
    Create an port forward to the ArgoCD server service, and open that page in a web browser
    """
    # TODO remove the password stuff, since we can assume we're running on the network
    result = subprocess.run(
        "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={{.data.password}} | base64 -d".format(),
        shell=True,
        capture_output=True,
    )
    subprocess.run(
        f"echo {result.stdout.decode('utf-8')} | pbcopy",
        shell=True,
        capture_output=True,
    )
    # Open a new tab in the default browser to localhost:8080 with webbrowser
    webbrowser.open_new_tab("http://localhost:8080/argocd")

    # Port forward to the ArgoCD UI
    subprocess.run(
        "kubectl -n argocd port-forward svc/argocd-server -n argocd 8080:443",
        shell=True,
    )


def print_application_status(applications, show_updates=False, spin_char="-") -> None:
    """
    Iterate over a list of applications, getting their status, and then printing the name. Green means the application
    is up fully, yellow means the application is not healthy, but hasn't failed, and red means the application has
    failed. Also can print a spinner if show_updates is True.

    Args:
        applications (list): A list of application names
        show_updates (bool): Whether to print a spinner for each application
        spin_char (str): The character to use for the spinner
    """
    v1 = client.CustomObjectsApi()

    for app in applications:
        app = v1.get_namespaced_custom_object(
            group="argoproj.io",
            version="v1alpha1",
            name=app,
            namespace="argocd",
            plural="applications",
        )

        if "operationState" in app["status"]:
            phase = app["status"]["operationState"]["phase"]
        else:
            phase = "Failed"
        status = app["status"]["health"]["status"]

        if phase == "Failed":
            print(colored(app["metadata"]["name"], "red"), end=" ")
        elif status != "Healthy":
            print(colored(app["metadata"]["name"], "yellow"), end=" ")
        else:
            print(colored(app["metadata"]["name"], "green"), end=" ")

        if show_updates:
            if phase == "Failed" or status != "Healthy":
                print(spin_char)
            else:
                print("✔")
        else:
            print()


def setup_argocd(args_dict: dict[str, str]) -> None:
    install_argocd(args_dict["environment"])
    install_master_stack(args_dict)


# TODO determine if this is going to be an internal-only function, or if we want to expost it
def sync_master_stack_application(application: str) -> None:
    """
    Run a sync operation against the master stack application, only syncing the specified application
    application

    Args:
        application (str): The name of the application to sync. It must be a sub-application of the master-stack
    """
    token = _get_argocd_bearer_token()

    response = requests.post(
        f"{settings.argocd_url}/api/v1/applications/master-stack/sync",
        data=json.dumps(
            {
                "resources": [
                    {
                        "kind": "Application",
                        "name": application,
                        "namespace": "argocd",
                        "group": "argoproj.io",
                    }
                ]
            }
        ),
        verify=False,
        headers={"Authorization": f"Bearer {token}"},
    )

    if response.status_code == 200:
        logging.info(f"Synced {application} successfully")
    else:
        logging.error(f"Failed to sync {application}")
        logging.error(response.text)


def _apply_master_stack_object(args_dict: dict[str, str], custom_objects_api) -> None:
    """
    Apply the master-stack object to the ArgoCD cluster. This is the object that creates all of our applications
    Args:
        args_dict (dict[str, str]): The dictionary of arguments to fill out the master-stack template
    """
    master_app_string = template_utils.template_file("master-app.yaml", args_dict)
    master_app_dict = yaml.safe_load(master_app_string)
    custom_objects_api.create_namespaced_custom_object(
        group="argoproj.io",
        version="v1alpha1",
        namespace="argocd",
        plural="applications",
        body=master_app_dict,
        pretty=True,
    )


def _get_argocd_bearer_token() -> str:
    """
    Get a bearer token for authenticating with the ArgoCD API. Takes no arguments, because we get a username and
    password for ArgoCD from environment variables
    Return:
        token (str): A bearer token for authenticating with the ArgoCD API.
    """
    # Get an auth token, using the configured
    auth_response = requests.post(
        f"{settings.argocd_url}/api/v1/session",
        data=json.dumps(
            {"username": settings.argocd_username, "password": settings.argocd_password}
        ),
        verify=False,
    )

    token = auth_response.json()["token"]
    return token


def _get_master_stack_application() -> dict:
    """
    Get an object representing the master-stack application, located in the ArgoCD namespace
    Return:
        api_response (object): An object representing the master-stack application, located in the ArgoCD namespace
    """
    try:
        api_instance = client.CustomObjectsApi()

        # Get the master-stack application, located in the ArgoCD namespace. This is what should be creating all of
        # our applications, so we want disable the target application in master-stacks parameters, so it doesn't
        # recreate it
        namespace = "argocd"
        name = "master-stack"
        group = "argoproj.io"
        version = "v1alpha1"
        plural = "applications"
        api_response = api_instance.get_namespaced_custom_object(
            group, version, namespace, plural, name
        )

        return api_response
    except Exception as e:
        logging.error("Failed to get master-stack application, see error below")
        print(e)
    return {}


def _get_source_helm_params(api_response: dict) -> list[dict[str, str]]:
    """
    Get the helm parameters from the api_response object. Will throw an error if no helm parameters are found.
    Args:
        api_response (object): The object representing the application, like a YAML output
    Return:
        source_helm_params (object): The helm parameters from the api_response object.
    """
    source_helm_params = (
        api_response.get("spec", {})
        .get("source", {})
        .get("helm", {})
        .get("parameters", [])
    )

    if not source_helm_params:
        logging.error("No helm parameters found")
        sys.exit(1)
    else:
        return source_helm_params


def _is_application_active(application: str, resources: dict) -> bool:
    """
    Check whether an application is active, i.e. whether or not it is in the list of resources created by master stack
    Args:
        application (str): The name of the application to check
        resources (list): A list of resources created by the master stack
    Return:
        bool: True if an application with the name matching the 'application' argument exists, and false otherwise
    """
    for resource in resources:
        if (
            resource.get("kind") == "Application"
            and resource.get("name") == application
        ):
            return True
    return False


def _is_application_enabled_in_master_stack(
    application: str, application_dict: dict
) -> bool:
    """
    Check if an application is enabled in master stack, i.e. the value 'application'.enabled is set.
    By default, its true, so it should only exist if its set to false.
    Args:
        application (str): The name of the application to check
        application_oject (object): The object representing the application, as returned by the ArgoCD API
    Return:
        bool: True if the application is enabled in master stack, and false otherwise.
    """
    source_helm_params = _get_source_helm_params(application_dict)
    for variable in source_helm_params:
        if application in variable.get("name"):  # type: ignore
            return False
    return True


def _wait_for_argocd_pods_to_be_ready() -> None:
    """
    Wait for all the ArgoCD pods to be up and healthy. We'll also print them with a
    fun spinner
    """
    # TODO Make timeout configurable
    v1 = client.CoreV1Api()
    timeout = time.time() + 60 * 5  # 5 minutes from now
    spinner = itertools.cycle(["-", "\\", "|", "/"])

    done_waiting = False

    # Check if all the pods are ready in a loop. If they aren't, we just print a waiting message with a spinner
    # This will time out after five minutes
    while not done_waiting:
        pods = v1.list_namespaced_pod("argocd")
        all_healthy = True
        for pod in pods.items:
            if pod.status.phase != "Running":
                all_healthy = False
                break
        if all_healthy:
            logging.info("ArgoCD pods are all healthy and ready")
            done_waiting = True
        if time.time() > timeout:
            logging.error(
                "Timeout reached, exiting. This is not an error with atils, there is likely something going"
                + " on in the cluster"
            )
            exit(1)

        print("Waiting for argocd pods to come up healthy " + next(spinner), end="\r")
        time.sleep(0.25)
