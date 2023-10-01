import logging
import argparse
import sys
import yaml
import subprocess
import webbrowser
import itertools
import time

from atils import atils_kubernetes as k8s_utils

from atils.common import config
from atils.common.config import settings
from atils.common import template_utils

from termcolor import colored
from kubernetes import config as k8s_config
from kubernetes import client

k8s_config.load_kube_config()  # type: ignore
client.rest.logger.setLevel(logging.WARNING)

# TODO make it so that logging is set up using config stored in config.py
logging.basicConfig(config.get_logging_level())  # type: ignore


def main(args: list[str]):
    parser: argparse.ArgumentParser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(
        help="Commands to manage argocd", dest="subparser_name"
    )

    install_parser = subparsers.add_parser("install", help="Install and set up ArgoCD")
    install_parser.add_argument(
        "environment",
        choices=["dev-laptop", "dev-cluster", "prod-cluster"],
        help="Which environment to use for templating",
    )

    port_forward_parser = subparsers.add_parser(
        "port-forward",
        help="Automatically port fowards ArgoCD, opens a browser, and copies the password",
    )

    grab_password_parser = subparsers.add_parser(
        "get-password", help="Get the admin password using the default secret."
    )

    print_apps_parser = subparsers.add_parser("test")

    disable_parser = subparsers.add_parser(
        "disable",
        help="Disables an application from the master stack",
    )
    disable_parser.add_argument("application", help="Which application to disable")

    enable_parser = subparsers.add_parser(
        "enable",
        help="Ensables an application from the master stack",
    )
    enable_parser.add_argument("application", help="Which application to ensable")

    if len(args) == 0:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args(args)

    if args.subparser_name == "install":
        args_dict = vars(args)
        if args_dict["environment"] is None:
            logging.error("Please provide an environment")
            sys.exit(1)
        else:
            setup_argocd(args_dict["environment"])
    elif args.subparser_name == "port-forward":
        open_argocd_port_forward()
    elif args.subparser_name == "disable":
        args_dict = vars(args)
        if args_dict["application"] is None:
            logging.error("Please provide an application name")
            sys.exit(1)
        else:
            disable_application(args_dict["application"])
    elif args.subparser_name == "enable":
        args_dict = vars(args)
        if args_dict["application"] is None:
            logging.error("Please provide an application name")
            sys.exit(1)
        else:
            enable_application(args_dict["application"])
    elif args.subparser_name == "get-password":
        get_argocd_password()
    elif args.subparser_name == "test":
        print_application_status(["grafana-loki", "gateways"], True)
    else:
        logging.error(f"Invalid command: ${args.subparser_name}")
        exit(1)


def get_argocd_password():
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


def enable_application(application: str) -> None:
    try:
        api_instance = client.CustomObjectsApi()

        # Get the argocd Application master-stack in the namespace argocd
        namespace = "argocd"
        name = "master-stack"
        group = "argoproj.io"
        version = "v1alpha1"
        plural = "applications"
        api_response = api_instance.get_namespaced_custom_object(
            group, version, namespace, plural, name
        )

        resources = api_response.get("status").get("resources")

        is_active = False
        is_disabled = False

        # Iterate over the resources and check for the specified application
        for resource in resources:
            if (
                resource.get("kind") == "Application"
                and resource.get("name") == application
            ):
                is_active = True
                break

        # If only step 2 is true, add a helm parameter application.enabled=false
        source = api_response.get("spec").get("source")
        if "helm" in source:
            if "parameters" in source.get("helm"):
                for variable in source.get("helm").get("parameters"):
                    if application in variable.get("name"):
                        is_disabled = True
                        break

        if not is_disabled:
            logging.info(f"Application {application} already enabled")
            exit(0)
        elif not is_active and is_disabled:
            # Check if field source.helm.parameters exists
            source_helm_params = (
                api_response.get("spec", {})
                .get("source", {})
                .get("helm", {})
                .get("parameters", [])
            )
            if not source_helm_params:
                logging.error(
                    "Error: Field source.helm.parameters does not exist in the application."
                )
                sys.exit(1)

            edited_parameters = source_helm_params

            for i in range(len(edited_parameters)):
                if application == edited_parameters[i].get("name").split(".")[0]:
                    del edited_parameters[i]

            print(edited_parameters)

            # Create JSON merge patch to update the helm parameters
            json_patch = {
                "spec": {"source": {"helm": {"parameters": edited_parameters}}}
            }

            # Use patch_namespaced_custom_object to update the application with the new helm parameter
            api_response = api_instance.patch_namespaced_custom_object(
                group, version, namespace, plural, name, json_patch
            )

            logging.info(f"{application} successfully enabled")

        else:
            logging.error(
                f"Error: Application '{application}' not found in the master-stack"
            )
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def disable_application(application: str) -> None:
    try:
        api_instance = client.CustomObjectsApi()

        # Get the argocd Application master-stack in the namespace argocd
        namespace = "argocd"
        name = "master-stack"
        group = "argoproj.io"
        version = "v1alpha1"
        plural = "applications"
        api_response = api_instance.get_namespaced_custom_object(
            group, version, namespace, plural, name
        )

        resources = api_response.get("status").get("resources")

        is_active = False
        is_disabled = False

        # Iterate over the resources and check for the specified application
        for resource in resources:
            if (
                resource.get("kind") == "Application"
                and resource.get("name") == application
            ):
                is_active = True
                break

            # If only step 2 is true, add a helm parameter application.enabled=false
        source = api_response.get("spec").get("source")
        if "helm" in source:
            if "parameters" in source.get("helm"):
                for variable in source.get("helm").get("parameters"):
                    if variable.get("name") in application:
                        is_disabled = True
                        break

        if is_disabled:
            logging.info(f"Application {application} already disabled")
            exit(0)
        elif is_active and not is_disabled:
            # Check if field source.helm.parameters exists
            source_helm_params = (
                api_response.get("spec", {})
                .get("source", {})
                .get("helm", {})
                .get("parameters", [])
            )
            if not source_helm_params:
                logging.error(
                    "Error: Field source.helm.parameters does not exist in the application."
                )
                sys.exit(1)

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

            logging.info(f"{application} successfully disabled")

        else:
            logging.error(
                f"Error: Application '{application}' not found in the master-stack"
            )
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


# TODO Just read the name of our current context to get the environment
def setup_argocd(environment: str):
    custom_objects_api = client.CustomObjectsApi()
    if not k8s_utils.check_namespace_exists("argocd"):
        api = client.CoreV1Api()

        # Create the namespace
        namespace_body = client.V1Namespace(metadata=client.V1ObjectMeta(name="argocd"))
        api.create_namespace(namespace_body)

    result = subprocess.run(
        f"""helm repo add argo https://argoproj.github.io/argo-helm && helm -n argocd upgrade --install argocd -f {config.SCRIPT_INSTALL_DIRECTORY}/../kubernetes/argocd/values.yaml argo/argo-cd""",
        shell=True,
        capture_output=True,
    )

    if result.returncode == 0:
        logging.info("ArgoCD Helm chart successfully installed")
    else:
        logging.warning(result.stdout)
        logging.warning(
            "ArgoCD Helm chart failed to install. This may simply be because it is already installed, which we don't check"
        )

    v1 = client.CoreV1Api()
    timeout = time.time() + 60 * 5  # 5 minutes from now
    spinner = itertools.cycle(["-", "\\", "|", "/"])

    while True:
        pods = v1.list_namespaced_pod("argocd")
        all_healthy = True
        for pod in pods.items:
            if pod.status.phase != "Running":
                all_healthy = False
                break
        if all_healthy:
            logging.info("Argocd pods are ready, installing master-stack")
            break
        if time.time() > timeout:
            logging.error(
                "Timeout reached, exiting. Check kubernetes to figure out what happened."
            )
            exit(1)

        print("Waiting for argocd pods to come up healthy " + next(spinner), end="\r")
        time.sleep(0.25)

    master_app_string = template_utils.template_file(
        "master-app.yaml", {"environment": environment}
    )
    master_app_dict = yaml.safe_load(master_app_string)

    # Check whether an argocd application named 'master-stack' exists
    try:
        custom_objects_api.get_namespaced_custom_object(
            group="argoproj.io",
            version="v1alpha1",
            namespace="argocd",
            plural="applications",
            name="master-stack",
        )
    except client.exceptions.ApiException as e:
        if e.status == 404:
            logging.info("No application named 'master-stack' exists, creating it")
            custom_objects_api.create_namespaced_custom_object(
                group="argoproj.io",
                version="v1alpha1",
                namespace="argocd",
                plural="applications",
                body=master_app_dict,
                pretty=True,
            )
        else:
            logging.info(
                "Master-stack already exists. If you want to force a recreation, use --force-master-reconfiguration[Not yet working]"
            )

    # applications = get_tracked_applications()
    # LINE_UP = f"\033[{len(applications)}A"
    # LINE_CLEAR = "\x1b[2K"

    # while True:
    #     print_application_status(applications, True, next(spinner))
    #     time.sleep(0.25)
    #     print(LINE_UP, end=LINE_CLEAR)


def open_argocd_port_forward():
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


def print_application_status(applications, show_updates=False, spin_char="-"):
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


def get_tracked_applications():
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
