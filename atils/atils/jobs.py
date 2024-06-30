import argparse
import itertools
import json
import logging
import os
import sys
import termios
import time
import tty
from threading import Thread
from typing import Any, List

import yaml
from kubernetes.client.rest import ApiException
from kubernetes.stream import stream

from atils import atils_kubernetes
from atils.common import config, console_utils, template_utils
from kubernetes import client
from kubernetes import config as k8s_config
from kubernetes import utils

client.rest.logger.setLevel(logging.ERROR)

logging.basicConfig(level=config.get_logging_level())  # type: ignore


def main(args: str) -> None:
    # This variable tracks whether or not we have configuration available to run kubernetes commands
    CAN_RUN: bool = atils_kubernetes.load_config()

    if not CAN_RUN:
        logging.error("No configuration available to run kubernetes commands")
        exit(1)

    parser: argparse.ArgumentParser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(
        help="Commands to manage kubernetes jobs", dest="subparser_name"
    )

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("job_name", help="Name of the job to run")
    # TODO Add some values for jobs, if needed, so we can set them with this argument
    run_parser.add_argument(
        "--set",
        help="Set values to fill in job template. WIP, not currently working",
        nargs=2,
        action="append",
        dest="values",
    )

    pvc_parser = subparsers.add_parser("manage-pvc")
    pvc_parser.add_argument(
        "--pvc-name", "-pn", help="The name of the PVC to launch a management pod for"
    )
    pvc_parser.add_argument(
        "--namespace",
        "-n",
        help="The namespace the PVC is located in. Defaults to current namespace",
    )

    postgres_parser = subparsers.add_parser("postgres-manager")

    devterm_parser = subparsers.add_parser("devterm")
    devterm_parser.add_argument(
        "--namespace",
        "-n",
        help="The namespace to launch the devterm in. Defaults to current namespace",
    )

    list_parser = subparsers.add_parser("list")

    describe_parser = subparsers.add_parser("describe")
    describe_parser.add_argument("job_name", help="Then name of the job to describe")

    arguments: argparse.Namespace = parser.parse_args(args)

    if arguments.subparser_name == "run":
        args_dict = vars(arguments)
        job_args = {}

        if args_dict["values"] is not None:
            for arg in args_dict["values"]:
                job_args[arg[0]] = arg[1]

        jobconfig_args = _get_arguments_from_jobconfig(args_dict["job_name"])

        args_filled_from_command_lines = _fill_out_jobconfig_args_from_command_line(
            jobconfig_args, job_args
        )

        if "" in args_filled_from_command_lines.values():
            final_job_args = _get_missing_arguments_interactive(
                args_filled_from_command_lines
            )
        else:
            final_job_args = args_filled_from_command_lines

        run_job(arguments.job_name, final_job_args)
    elif arguments.subparser_name == "manage-pvc":
        args_dict = vars(arguments)
        current_namespace = atils_kubernetes.get_current_namespace()

        if "namespace" in args_dict.keys():
            if args_dict.get("namespace") is not None:
                launch_pvc_manager(args_dict["pvc_name"], args_dict["namespace"])
            else:
                launch_pvc_manager(args_dict["pvc_name"], current_namespace)
        else:
            launch_pvc_manager(args_dict["pvc_name"], current_namespace)
    elif arguments.subparser_name == "postgres-manager":
        launch_postgres_manager()
    elif arguments.subparser_name == "devterm":
        namespace: str = ""
        args_dict: dict = vars(arguments)

        if args_dict["namespace"] is not None:
            namespace = args_dict["namespace"]
        else:
            namespace = atils_kubernetes.get_current_namespace()

        launch_devterm_pod(namespace)
    elif arguments.subparser_name == "list":
        list_available_jobs()
    elif arguments.subparser_name == "describe":
        args_dict = vars(arguments)
        describe_job(args_dict["job_name"])
    else:
        logging.error(f"Unrecognized command {arguments.subparser_name}")
        exit(1)


def describe_job(job_name: str) -> None:
    """
    Using the .atils_jobconfig.json file, describe a job's purpose, as well as any arguments it takes.

    Args:
        job_name (str): The name of the job to describe
    """
    jobs_dir = config.get_full_atils_dir("JOBS_DIR")
    dir_for_job = os.path.join(jobs_dir, job_name)

    if os.path.exists(dir_for_job):
        jobconfig_path = os.path.join(dir_for_job, ".atils_jobconfig.json")

        if os.path.exists(jobconfig_path):
            with open(jobconfig_path) as file:
                jobconfig_data = json.load(file)
                console_utils.print_jobconfig(jobconfig_data)
        else:
            logging.error(
                f"Job {job_name} does not have a jobconfig. It probably will not run successfully"
            )
            exit(1)
    else:
        logging.error(f"Job {job_name} does not exist")
        exit(1)

    return


def launch_postgres_manager() -> None:
    """
    Launch a postgres client pod, connected to the master user
    """
    pod_manifest: dict[str, Any] = {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {"name": "postgres-manager"},
        "spec": {
            "containers": [
                {
                    "name": "postgres-manager",
                    "image": "aidanhilt/atils-postgres-client",
                    "command": ["sh", "-c", "sleep 1800"],
                    "env": [
                        {
                            "name": "PGHOST",
                            "value": "postgres-postgresql.postgres.svc.cluster.local",
                        },
                        {"name": "PGUSER", "value": "postgres"},
                        {
                            "name": "PGPASSWORD",
                            "valueFrom": {
                                "secretKeyRef": {
                                    "name": "postgres-config",
                                    "key": "postgres-password",
                                }
                            },
                        },
                        {"name": "PGDATABASE", "value": "postgres"},
                    ],
                }
            ],
            "restartPolicy": "Never",
        },
    }
    _create_pod_if_not_existent("postgres-manager", pod_manifest, "postgres")
    _exec_shell_in_pod(
        "postgres-manager", "postgres", "postgres-manager", ["psql"], True
    )


def launch_devterm_pod(namespace: str) -> None:
    """
    Launch a pod with assorted devterm utils
    """
    pod_manifest: dict[str, Any] = {
        "apiVersion": "v1",
        "kind": "Pod",
        "metadata": {"name": "atils-devterm"},
        "spec": {
            "serviceAccountName": "debug-job",
            "containers": [
                {
                    "name": "atils-devterm",
                    "image": "aidanhilt/atils-debug",
                    "command": ["sh", "-c", "sleep 1800"],
                }
            ],
            "restartPolicy": "Never",
        },
    }
    _ensure_access_exists("debug-job", namespace, "admin", True)
    _create_pod_if_not_existent("atils-devterm", pod_manifest, namespace)
    _exec_shell_in_pod("atils-devterm", namespace, "atils-devterm", delete=True)


def launch_pvc_manager(pvc_name: str, namespace: str) -> None:
    """
    Given the name of a PVC, and the namespace it lives in, launch some kind of container that mounts it

    Args:
        pvc_name (str): The name of the PVC to launch a management container for
        namespace (str): The namespace the PVC is located in
    """
    pod_name = _find_pod_by_pvc(pvc_name)

    if pod_name != "" and pod_name != "pvc-manager":
        volume_name = _find_volume_by_pvc_and_pod(pod_name, namespace, pvc_name)
        _delete_pvc_manager_if_exists(pod_name, namespace)

        time.sleep(6)

        _patch_pod_with_devterm_container(pod_name, namespace, volume_name)
    else:
        _create_pvc_manager_pod(pvc_name, namespace)

        pod_name = "pvc-manager"
        volume_name = pvc_name

    time.sleep(5)

    _exec_shell_in_pod(pod_name, namespace, "pvc-manager")


def list_available_jobs() -> None:
    # TODO exclude the docs directory, include a list of valid arguments
    """
    Print all the jobs available to run in the jobs directory to the console
    """
    jobs_dir = config.get_full_atils_dir("JOBS_DIR")

    root, dirs, files = next(os.walk(jobs_dir))
    for job in dirs:
        if job != "docs":
            jobconfig_path = os.path.join(jobs_dir, job, ".atils_jobconfig.json")
            if os.path.exists(jobconfig_path):
                with open(jobconfig_path) as file:
                    jobconfig_data = json.load(file)
                    description = jobconfig_data["short_description"]

                print(f"{job}:      {description}")


def run_job(job_name: str, args=None) -> None:
    """
    Given a job name and list of args, render the job template, then run the job
    Args:
        job_name (str): The name of the job to run. Must be a directory in the JOBS_DIR directory
        args (dict[str, str]): A dictionary representing arguments. Each key should correspond to a
        variable in a job template, with each value representing what should be filled in
    """
    rendered_job = _render_job(job_name, args)
    _launch_job(rendered_job)
    logging.info(f"Job {job_name} created")


def _clear_job_name(job_name: str, namespace: str) -> None:
    """
    We don't do a GenerateName for our jobs, so we need to make sure that the generated job name is available.
    So given a job name, and a namespace, delete the job, and then make sure it's deleted before letting us out
    """
    # Get all the jobs in the namespace, and then loop over them, looking for a matching name field
    # If found, we'll then delete the job, and wait for it to clear out
    v1 = client.BatchV1Api()
    for job in v1.list_namespaced_job(namespace).items:
        if job.metadata.name == job_name:
            # TODO Let's also delete all pods associated with the job
            # TODO the best way to do that is going to be to try and get a pod with all the matching labels,
            # so let's just refactor to not be afraid of error handling
            v1.delete_namespaced_job(name=job_name, namespace=namespace)
            # Wait until the job is deleted
            dots = itertools.cycle([".  ", ".. ", "..."])
            spinner = itertools.cycle(["-", "\\", "|", "/"])

            # TODO split out the waiting logic
            job = v1.read_namespaced_job(name=job_name, namespace=namespace)
            while job:
                try:
                    job = v1.read_namespaced_job(name=job_name, namespace=namespace)
                    print(
                        f"Waiting for job {job_name} to be deleted{next(dots)} {next(spinner)}",
                        end="\r",
                    )
                    time.sleep(0.2)
                except client.rest.ApiException as e:
                    if e.status == 404:
                        job = None
                    else:
                        raise e
            print("\n")
            logging.info(f"Job {job_name} deleted")
            return
    logging.info(f"No job named {job_name} found in namespace {namespace}")


def _create_pod_if_not_existent(
    pod_name: str, pod_manifest: dict[str, Any], namespace: str = "default"
) -> None:
    # TODO we can make this generic with a ton of arguments
    """
    Create a pod that we want to exec into (generally) if one doesn't exist. We're also going to wait for it
    to be ready

    Args:
        pod_name (str): The name of the pod we will want to create
        pod_manifest (dict[str, Any]): A dictionary representing a valid Kubernetes pod object
        namespace: The namespace this pod will be launched in. Defaults to "default"
    """
    try:
        api_instance = client.CoreV1Api()

        try:
            existing_pod = api_instance.read_namespaced_pod(
                name=pod_name, namespace=namespace
            )

            # TODO right now, we might get kicked out of our pod if it's close to expiring. That's probably
            # not a big deal, but if so, fix it here
            if existing_pod:
                logging.info(
                    f"There's already a {pod_name} pod! We're just gonna leave it"
                )
                return
        except ApiException as e:
            if e.status != 404:
                logging.error(
                    f"Error checking for existing pod 'postgres-manager': {str(e)}"
                )
                exit(1)

        try:
            # Create the pod
            api_instance.create_namespaced_pod(namespace=namespace, body=pod_manifest)
            logging.info(f"Created pod '{pod_name}' in {namespace} namespace")

            # Now, let's wait for it to be ready
            pod_ready = False
            while not pod_ready:
                pod = api_instance.read_namespaced_pod(
                    name=pod_name, namespace=namespace
                )

                if pod.status.phase == "Running":
                    for container in pod.status.container_statuses:
                        if not container.ready:
                            break
                    else:
                        print(f"Pod {pod_name} is ready.")
                        return

                time.sleep(0.5)

        except client.rest.ApiException as e:
            logging.error(f"Error creating pod '{pod_name}': {str(e)}")

    except Exception as e:
        logging.error(f"Error occurred while creating pod 'postgres-manager': {str(e)}")


def _create_pvc_manager_pod(pvc_name: str, namespace: str) -> None:
    try:
        api_instance = client.CoreV1Api()

        # Check if a pod named "pvc-manager" already exists in the namespace
        try:
            existing_pod = api_instance.read_namespaced_pod(
                name="pvc-manager", namespace=namespace
            )
            if existing_pod:
                # Delete the existing "pvc-manager" pod
                api_instance.delete_namespaced_pod(
                    name="pvc-manager", namespace=namespace, grace_period_seconds=0
                )
                logging.info(
                    f"Deleted existing pod 'pvc-manager' in namespace '{namespace}'"
                )
                time.sleep(5)  # Wait for the pod to be deleted
        except ApiException as e:
            if e.status != 404:
                logging.error(
                    f"Error checking/deleting existing pod 'pvc-manager': {str(e)}"
                )

        # Define the pod manifest
        pod_manifest = {
            "apiVersion": "v1",
            "kind": "Pod",
            "metadata": {"name": "pvc-manager"},
            "spec": {
                "containers": [
                    {
                        "name": "pvc-manager",
                        "image": "aidanhilt/atils-devterm",
                        "command": ["/bin/sh"],
                        "args": [
                            "-c",
                            "sleep 1800",
                        ],  # Sleep for 30 minutes (1800 seconds)
                        "volumeMounts": [
                            {"name": "pvc", "mountPath": f"/root/{pvc_name}"}
                        ],
                    }
                ],
                "volumes": [
                    {"name": "pvc", "persistentVolumeClaim": {"claimName": pvc_name}}
                ],
                "restartPolicy": "Never",
            },
        }

        try:
            # Create the pod
            api_instance.create_namespaced_pod(namespace=namespace, body=pod_manifest)
            logging.info(
                f"Created pod 'pvc-manager' with PVC '{pvc_name}' mounted at '/root/{pvc_name}'"
            )
        except client.rest.ApiException as e:
            logging.error(f"Error creating pod 'pvc-manager': {str(e)}")

    except Exception as e:
        logging.error(f"Error occurred while creating pod: {str(e)}")


def _delete_pvc_manager_if_exists(pod_name: str, namespace: str) -> None:
    try:

        api_instance = client.CoreV1Api()

        try:
            # Get the pod details
            pod = api_instance.read_namespaced_pod(name=pod_name, namespace=namespace)

            # Check if the pod has ephemeral containers
            if pod.spec.ephemeral_containers:
                # Find the index of the "pvc-manager" ephemeral container
                container_index = next(
                    (
                        index
                        for index, container in enumerate(pod.spec.ephemeral_containers)
                        if container.name == "pvc-manager"
                    ),
                    None,
                )

                if container_index is not None:
                    # Remove the "pvc-manager" ephemeral container from the pod spec
                    pod.spec.ephemeral_containers.pop(container_index)

                    # Patch the pod to update the ephemeral containers
                    api_instance.patch_namespaced_pod(
                        name=pod_name, namespace=namespace, body=pod
                    )
                    logging.devterm(
                        f"Deleted ephemeral container 'pvc-manager' from pod '{pod_name}'"
                    )
                else:
                    logging.devterm(
                        f"Ephemeral container 'pvc-manager' not found in pod '{pod_name}'"
                    )
            else:
                logging.devterm(f"No ephemeral containers found in pod '{pod_name}'")

        except ApiException as e:
            if e.status == 404:
                logging.warning(
                    f"Pod '{pod_name}' not found in namespace '{namespace}'"
                )
            else:
                logging.error(
                    f"Error deleting ephemeral container from pod '{pod_name}': {str(e)}"
                )

    except Exception as e:
        logging.error(f"Error occurred while deleting ephemeral container: {str(e)}")


def _ensure_access_exists(
    service_account_name: str,
    service_account_namespace: str,
    role_name: str,
    cluster_role: bool = False,
) -> None:
    """
    Given a service account, ensure that it's bound to either a Role, or a ClusterRole based on the cluster_role arg

    Args:
        service_account_name (str): The name of the service account we want to use for our job
        service_account_namespace (str): The namespace our chosen service account lives in
        role_name (str): The name of the role our service account needs to be bound to. If cluster_role is set to True, this is a ClusterRole,
        and it is a namespaced role otherwise
    """

    # Create API clients
    v1 = client.CoreV1Api()
    rbac_v1 = client.RbacAuthorizationV1Api()

    # 1. Check if the service account exists
    try:
        v1.read_namespaced_service_account(
            name=service_account_name, namespace=service_account_namespace
        )
    except ApiException as e:
        if e.status == 404:
            logging.error(
                f"Service account {service_account_name} does not exist in namespace {service_account_namespace}."
            )
            exit(1)
        else:
            logging.error(f"Error checking service account: {e}")
            exit(1)

    # 2. Check if the role/cluster role exists
    try:
        if cluster_role:
            rbac_v1.read_cluster_role(name=role_name)
        else:
            rbac_v1.read_namespaced_role(
                name=role_name, namespace=service_account_namespace
            )
    except ApiException as e:
        if e.status == 404:
            logging.error(
                f"{'ClusterRole' if cluster_role else 'Role'} {role_name} does not exist."
            )
            return
        else:
            logging.error(
                f"Error checking {'cluster role' if cluster_role else 'role'}: {e}"
            )
            return

    # 3. Check and create role binding if necessary
    binding_name = f"{service_account_name}-{role_name}"
    try:
        if cluster_role:
            rbac_v1.read_cluster_role_binding(name=binding_name)
        else:
            rbac_v1.read_namespaced_role_binding(
                name=binding_name, namespace=service_account_namespace
            )
        print(
            f"{'ClusterRoleBinding' if cluster_role else 'RoleBinding'} {binding_name} already exists."
        )
    except ApiException as e:
        if e.status == 404:
            # Create the binding
            if cluster_role:
                body = client.V1ClusterRoleBinding(
                    metadata=client.V1ObjectMeta(name=binding_name),
                    subjects=[
                        client.V1Subject(
                            kind="ServiceAccount",
                            name=service_account_name,
                            namespace=service_account_namespace,
                        )
                    ],
                    role_ref=client.V1RoleRef(
                        kind="ClusterRole",
                        name=role_name,
                        api_group="rbac.authorization.k8s.io",
                    ),
                )
                rbac_v1.create_cluster_role_binding(body=body)
            else:
                body = client.V1RoleBinding(
                    metadata=client.V1ObjectMeta(
                        name=binding_name, namespace=service_account_namespace
                    ),
                    subjects=[
                        client.V1Subject(
                            kind="ServiceAccount",
                            name=service_account_name,
                            namespace=service_account_namespace,
                        )
                    ],
                    role_ref=client.V1RoleRef(
                        kind="Role",
                        name=role_name,
                        api_group="rbac.authorization.k8s.io",
                    ),
                )
                rbac_v1.create_namespaced_role_binding(
                    namespace=service_account_namespace, body=body
                )
            print(
                f"Created {'ClusterRoleBinding' if cluster_role else 'RoleBinding'} {binding_name}"
            )
        else:
            print(
                f"Error checking {'cluster role binding' if cluster_role else 'role binding'}: {e}"
            )


def _exec_shell_in_pod(
    pod_name: str,
    namespace: str,
    container_name: str,
    exec_command: list[str] = ["/bin/zsh"],
    delete: bool = False,
) -> None:
    """
    Exec into a given container in a given pod, in a given namespace. This will assume
    that the container has zsh installed

    Args:
        pod_name (str): The name of the pod to exec into
        namespace (str): The namespace the pod is located in
        container_name (str): The name of the container to exec into
    """
    api_client = client.ApiClient()
    api_instance = client.CoreV1Api(api_client)

    resp = stream(
        api_instance.connect_get_namespaced_pod_exec,
        pod_name,
        namespace,
        command=exec_command,
        container=container_name,
        stderr=True,
        stdin=True,
        stdout=True,
        tty=True,
        _preload_content=False,
    )

    t = Thread(target=_read, args=[resp])

    # change tty mode to be able to work with escape characters
    stdin_fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(stdin_fd)
    try:
        tty.setraw(stdin_fd)
        t.start()
        while resp.is_open():
            data = resp.read_stdout(10)
            if resp.is_open():
                if len(data or "") > 0:
                    sys.stdout.write(data)
                    sys.stdout.flush()
    finally:
        # reset tty
        if delete:
            api_instance.delete_namespaced_pod(pod_name, namespace)
        print("\033c")
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_settings)
        print("press enter")


def _fill_out_jobconfig_args_from_command_line(
    jobconfig_args: dict, command_line_args: dict
) -> dict[str, str]:
    """
    Fill out the jobconfig_args dictionary with the c.

    Args:
        jobconfig_args (dict): The dictionary to fill out
        command_line_args (dict): The dictionary containing the command line arguments

    Returns:
        dict: The updated jobconfig_args dictionary
    """
    for key, value in command_line_args.items():
        jobconfig_args[key] = value
    return jobconfig_args


def _find_pod_by_pvc(pvc_name: str) -> str:
    """
    Given the name of a PVC, find the name of a pod it is attached to. If no pod is attached, return an empty string

    Args:
        pvc_name (str): The name of the PVC to search for

    Returns:
        str: The name of the pod the PVC is attached to, or an empty string if no pod is attached.
    """
    try:

        v1 = client.CoreV1Api()

        # List all pods in all namespaces
        pods: List[client.V1Pod] = v1.list_pod_for_all_namespaces().items

        for pod in pods:
            for volume in pod.spec.volumes:
                if (
                    volume.persistent_volume_claim
                    and volume.persistent_volume_claim.claim_name == pvc_name
                ):
                    return pod.metadata.name

        return ""

    except Exception as e:
        print(f"Error occurred while searching for pod: {str(e)}")
        return ""


def _find_volume_by_pvc_and_pod(pod_name: str, namespace: str, pvc_name: str) -> str:
    """
    Given a pvc name, and the name of a pod, find the name the volume was given, for mounting purposes.
    We assume there's a volume here, so fail if nothing is found

    Args:
        pod_name (str): The name of the pod to search for
        namespace (str): The namespace the pod is in
        pvc_name (str): The name of the PVC to search for

    Returns:
        str: The name of the volume that mounts our pvc
    """
    try:

        v1 = client.CoreV1Api()
        pod = v1.read_namespaced_pod(name=pod_name, namespace=namespace)

        for volume in pod.spec.volumes:
            if (
                volume.persistent_volume_claim
                and volume.persistent_volume_claim.claim_name == pvc_name
            ):
                return volume.name

        logging.error(
            f"No volume found using PVC '{pvc_name}' in pod '{pod_name}' in namespace '{namespace}'"
        )
        sys.exit(1)

    except Exception as e:
        logging.error(f"Error occurred while searching for volume: {str(e)}")
        sys.exit(1)


def _get_arguments_from_jobconfig(job_name: str) -> dict[str, str]:
    """
    Get the arguments from the jobconfig file.

    Args:
        job_name (str): The name of the job to get the arguments for

    Returns:
        dict[str, str]: A dictionary containing the arguments
    """
    try:
        jobs_dir = config.get_full_atils_dir("JOBS_DIR")
        if os.path.exists(os.path.join(jobs_dir, job_name, ".atils_jobconfig.json")):
            jobconfig_file = os.path.join(jobs_dir, job_name, ".atils_jobconfig.json")
        else:
            logging.error(f"No jobconfig found for job {job_name}, exiting")
            sys.exit(1)

        jobconfig_args = {}

        # Read the jobconfig file
        with open(jobconfig_file, "r") as file:
            jobconfig = json.load(file)

            if "args" in jobconfig.keys():
                for arg in jobconfig["args"]:
                    if "default" in arg.keys():
                        jobconfig_args[arg["name"]] = arg["default"]
                    else:
                        jobconfig_args[arg["name"]] = ""

        return jobconfig_args

    except Exception as e:
        logging.error(
            f"Error occurred while getting arguments from jobconfig: {str(e)}"
        )
        sys.exit(1)


def _get_missing_arguments_interactive(
    missing_args_dict: dict[str, str]
) -> dict[str, str]:
    """
    Get missing job arguments from the user.

    Args:
        missing_args_dict (dict[str, str]): A dictionary containing the missing arguments

    Returns:
        dict[str, str]: A dictionary containing the updated missing arguments
    """
    try:
        for arg_name, arg_value in missing_args_dict.items():
            if arg_value == "":
                arg_value = input(f"Enter value for {arg_name}: ")
                missing_args_dict[arg_name] = arg_value

        return missing_args_dict

    except Exception as e:
        logging.error(f"Error occurred while getting missing arguments: {str(e)}")
        sys.exit(1)


def _launch_job(job_dict):
    job_name = job_dict["metadata"]["name"]

    if "namespace" in job_dict["metadata"]:
        namespace = job_dict["metadata"]["namespace"]
    else:
        _, active_context = k8s_config.list_kube_config_contexts()
        if "namespace" in active_context["context"]:
            namespace = active_context["context"]["namespace"]
        else:
            namespace = "default"
        job_dict["metadata"]["namespace"] = namespace

    _clear_job_name(job_name, namespace)

    k8s_client = client.ApiClient()
    utils.create_from_dict(k8s_client, job_dict)


def _patch_pod_with_devterm_container(
    pod_name: str, namespace: str, volume_name: str
) -> None:
    """
    Patch a pod with an ephemeral container, running our devterm image. This then mounts a PVC in the home directory,
    to view and modify any files

    Args:
        pod_name (str): The name of the pod to patch
        namespace (str): The namespace the pod to patch lives in
        volume_name (str): The name of the volume to mount in the pod
    """
    try:

        api_instance = client.CoreV1Api()

        # Define the ephemeral container
        ephemeral_container = {
            "name": "pvc-manager",
            "image": "aidanhilt/atils-devterm",
            "command": ["/bin/sh"],
            "args": ["-c", "sleep 1800"],  # Sleep for 30 minutes (1800 seconds)
            "volumeMounts": [
                {"name": volume_name, "mountPath": f"/root/{volume_name}"}
            ],
        }

        body = {"spec": {"ephemeralContainers": [ephemeral_container]}}

        try:
            # Patch the pod with the ephemeral container
            api_instance.patch_namespaced_pod_ephemeralcontainers(
                name=pod_name, namespace=namespace, body=body
            )

            logging.devterm(
                f"Successfully patched pod '{pod_name}' with ephemeral container"
            )
        except Exception as e:
            logging.error(f"Error patching pod '{pod_name}': {str(e)}")

    except Exception as e:
        logging.error(f"Error occurred while patching pod: {str(e)}")


def _read(resp):
    """
    Redirect the terminal input to the stream, and read the response from the stream.
    This is used to read the response from the stream when we are running a job.
    Args:
        resp (stream): The stream object to read from.
    Returns:
        str: The response from the stream.
    """
    while resp.is_open():
        char = sys.stdin.read(1)
        resp.update()
        if resp.is_open():
            resp.write_stdin(char)


def _render_job(job_name: str, args: dict[str, str]) -> str:
    """
    Given the name of a job, that is the same as a directory in the JOBS_DIR directory,
    render the template with the arguments provided, and return it
    Args:
        job_name (str): The name a job in the JOBS_DIR directory
        args (dict[str, str]): A dictionary representing arguments. Each key should correspond to a
        variable in a job template, with each value representing what should be filled in
    Returns:
        str: The contents of the template file, rendered with the values of args
    """
    jobs_dir = config.get_full_atils_dir("JOBS_DIR")
    if os.path.exists(os.path.join(jobs_dir, job_name, "job.yaml")):
        rendered_job = template_utils.template_external_file(
            os.path.join(jobs_dir, job_name, "job.yaml"), args
        )
        return yaml.safe_load(rendered_job)

    else:
        logging.error(f'Job "{job_name}" was not found')
        exit(1)
