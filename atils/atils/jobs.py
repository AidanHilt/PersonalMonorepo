import argparse
import itertools
import logging
import os
import sys
import termios
import time
import tty
from threading import Thread
from typing import List

import yaml
from kubernetes.client.rest import ApiException
from kubernetes.stream import stream

from atils import atils_kubernetes
from atils.common import config, template_utils
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
        "--set", help="Set values to fill in job template. WIP, not currently working"
    )
    run_parser.add_argument("--tag", help="Image tag to use for the job")

    pvc_parser = subparsers.add_parser("manage-pvc")
    pvc_parser.add_argument(
        "--pvc-name", "-pn", help="The name of the PVC to launch a management pod for"
    )
    pvc_parser.add_argument(
        "--namespace",
        "-n",
        help="The namespace the PVC is located in. Defaults to current namespace",
    )

    list_parser = subparsers.add_parser("list")

    arguments: argparse.Namespace = parser.parse_args(args)

    if arguments.subparser_name == "run":
        job_args = {}

        args_dict = vars(args)
        if "image" in args_dict and args_dict["tag"] is not None:
            job_args["image_tag"] = args_dict["tag"]
        else:
            job_args["image_tag"] = "latest"

        run_job(arguments.job_name, job_args)
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
    elif arguments.subparser_name == "list":
        list_available_jobs()
    else:
        logging.error(f"Unrecognized command {arguments.subparser_name}")
        exit(1)


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

        _patch_pod_with_debug_container(pod_name, namespace, volume_name)
    else:
        _create_pvc_manager_pod(pvc_name, namespace)

        pod_name = "pvc-manager"
        volume_name = pvc_name

    time.sleep(5)

    _exec_shell_in_pod(pod_name, "videos", "pvc-manager")


def list_available_jobs() -> None:
    # TODO exclude the docs directory, include a list of valid arguments
    """
    Print all the jobs available to run in the jobs directory to the console
    """
    jobs_dir = config.get_full_atils_dir("JOBS_DIR")

    root, dirs, files = next(os.walk(jobs_dir))
    for job in dirs:
        description = "No description provided"
        description_location = os.path.join(jobs_dir, job, "description.txt")
        if os.path.exists(description_location):
            with open(description_location) as file:
                description = file.read()
                if len(description) > 250:
                    description = description[0:251] + "..."

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
                        "image": "aidanhilt/atils-debug",
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
                    logging.debug(
                        f"Deleted ephemeral container 'pvc-manager' from pod '{pod_name}'"
                    )
                else:
                    logging.debug(
                        f"Ephemeral container 'pvc-manager' not found in pod '{pod_name}'"
                    )
            else:
                logging.debug(f"No ephemeral containers found in pod '{pod_name}'")

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


def _exec_shell_in_pod(pod_name: str, namespace: str, container_name: str) -> None:
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

    exec_command = ["/bin/zsh"]

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
        print("\033c")
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_settings)
        print("press enter")


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


def _patch_pod_with_debug_container(
    pod_name: str, namespace: str, volume_name: str
) -> None:
    """
    Patch a pod with an ephemeral container, running our debug image. This then mounts a PVC in the home directory,
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
            "image": "aidanhilt/atils-debug",
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

            logging.debug(
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
