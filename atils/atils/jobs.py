import argparse
import itertools
import json
import logging
import os
import subprocess
import sys
import time

import yaml
from kubernetes.stream import stream

from atils import atils_kubernetes
from atils.common import config, template_utils
from atils.common.settings import settings
from kubernetes import client
from kubernetes import config as k8s_config
from kubernetes import dynamic, utils

k8s_config.load_kube_config()  # type: ignore
client.rest.logger.setLevel(logging.ERROR)

logging.basicConfig(level=config.get_logging_level())  # type: ignore


def main(args: str):
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
    run_parser.add_argument("--image", help="Image tag to use for the job")

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

    args = parser.parse_args(args)

    if args.subparser_name == "run":
        job_args = {}

        args_dict = vars(args)
        if "image" in args_dict and args_dict["image"] is not None:
            job_args["image_tag"] = args_dict["image"]
        else:
            job_args["image_tag"] = "latest"

        run_job_cli(args.job_name, job_args)
    elif args.subparser_name == "manage-pvc":
        args_dict = vars(args)
        current_namespace = atils_kubernetes.get_current_namespace()

        if "namespace" in args_dict.keys():
            if args_dict.get("namespace") is not None:
                launch_pvc_manager(args_dict["pvc_name"], args_dict["namepsace"])
            else:
                launch_pvc_manager(args_dict["pvc_name"], current_namespace)
        else:
            launch_pvc_manager(args_dict["pvc_name"], current_namespace)
    elif args.subparser_name == "list":
        list_available_jobs()
    else:
        logging.error(f"Unrecognized command {args.subparser_name}")
        exit(1)


def list_available_jobs():
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


def get_controller_from_pvc(pvc_name: str, namespace: str = ""):
    # TODO Validate that the PVC exists, so we can use it on PVCs without a pod
    # TODO We should probably break this into smaller, more testable functions. Once we have proper tests
    if not namespace:
        result = subprocess.run(
            ["kubectl", "describe", "pvc", pvc_name], capture_output=True, text=True
        )
    else:
        result = subprocess.run(
            ["kubectl", "describe", "pvc", pvc_name, "-n", namespace],
            capture_output=True,
            text=True,
        )

    pod_namespace = ""
    if namespace:
        pod_namespace = namespace

    pod_info = get_information_from_description(result.stdout)

    if len(pod_info["used_by"]) == 0:
        logging.error(
            f"Could not find a pod for {pvc_name}, try checking if it exists, or is attached"
        )
        exit(1)
    with client.ApiClient() as api_client:
        if pod_info["used_by"] != "<none>":
            api_instance = client.CoreV1Api(api_client)
            try:
                # TODO This may come back to bite me in the ass. If it grabs the wrong object, it's because we assume there's only one owner reference
                if namespace == "":
                    if "namespace" in pod_info.keys():
                        pod_namespace = pod_info["namespace"]

                api_response = api_instance.read_namespaced_pod(
                    pod_info["used_by"], pod_namespace
                )
                if api_response.metadata.owner_references is not None:
                    return (
                        api_response.metadata.owner_references[0].name,
                        pod_namespace,
                        api_response.metadata.owner_references[0].kind,
                    )
                else:
                    return None, None, None
            except client.exceptions.ApiException:
                logging.error(
                    f"Could not find pod {pod_info['used_by']} for pvc {pvc_name}"
                )
                exit(1)
        else:
            logging.info(
                f"Could not find a pod for pvc {pvc_name}, going to assume its currently unattached"
            )
            return None, None, None


def get_information_from_description(description: str):
    return_dict = {}
    # TODO error handle here if needed
    for line in description.split("\n"):
        if "Used By:" in line:
            splitted = line.split(" ")
            return_dict["used_by"] = splitted[len(splitted) - 1]
        elif "Namespace:" in line:
            splitted = line.split(" ")
            return_dict["namespace"] = splitted[len(splitted) - 1]
        elif "Controlled By:" in line:
            splitted = line.split(" ")
            raw_value = splitted[len(splitted) - 1]
            return_dict["controlled_by"] = raw_value.split("/")[1]
    return return_dict


def modify_controller_replicas(
    controller_name: str, namespace: str, controller_type: str, num_replicas: int
):
    with client.ApiClient() as api_client:
        api_instance = client.AppsV1Api(api_client)
        try:
            if controller_type == "ReplicaSet":
                result = subprocess.run(
                    [
                        "kubectl",
                        "describe",
                        "replicaset",
                        controller_name,
                        "-n",
                        namespace,
                    ],
                    capture_output=True,
                    text=True,
                )
                info = get_information_from_description(result.stdout)

                previous_replicas = api_instance.read_namespaced_deployment(
                    info["controlled_by"], namespace
                ).spec.replicas

                patch_body = (
                    '[{"op": "replace", "path": "/spec/replicas", "value":'
                    + str(num_replicas)
                    + "}]"
                )
                api_response = api_instance.patch_namespaced_deployment(
                    info["controlled_by"], namespace, json.loads(patch_body)
                )

                return previous_replicas
        except client.exceptions.ApiException as e:
            logging.error(f"Failed to scale down {controller_name}")
            logging.debug(e)


def launch_pvc_manager(pvc_name: str, namespace: str):
    if pvc_name is None:
        logging.error("--pvc-name must be provided")
        exit(1)
    else:
        # Scale down the controller, so we can get to the juicy pvc
        (
            controller_name,
            controller_namespace,
            controller_kind,
        ) = get_controller_from_pvc(pvc_name)
        previous_replicas = 1
        if controller_name is not None:
            previous_replicas = modify_controller_replicas(
                controller_name, controller_namespace, controller_kind, 0
            )

        with client.ApiClient() as api_client:
            # Launch the pod, probably with a kubectl command
            rendered_job = render_job("pvc-manager-interactive", {"pvc_name": pvc_name})
            launch_job(rendered_job)

            logging.info("Waiting 5 seconds for the job pod to come up")
            time.sleep(5)

            api_instance = client.CoreV1Api(api_client)
            pods = api_instance.list_namespaced_pod(
                namespace,
                # TODO This is hardcoded
                label_selector="job-name=pvc-manager-pvc-jellyfin",
                field_selector="status.phase!=Succeeded",
            )
            if len(pods.items) < 1:
                logging.error("Was not able to find any running pods for this job")
                exit(1)
            else:
                pod_name = pods.items[0].metadata.name
                exec_command = f"kubectl exec -it {pod_name} -- /bin/sh"

                subprocess.run(
                    f"echo {exec_command} | pbcopy",
                    shell=True,
                    capture_output=True,
                )
                print("Copied kubectl exec command to clipboard")

            # TODO I'd like to have this automatically open the pod, but that's a pain right now
            # response = stream(
            #     core_api_client.connect_get_namespaced_pod_exec(
            #         "qbittorrent-68cf455bb9-nzpvb",
            #         namespace=namespace,
            #         # container=rendered_job["spec"]["template"]["spec"]["containers"][0]["name"],
            #         container="qbittorrent",
            #         stdin=True,
            #         stdout=True,
            #         stderr=True,
            #         command="/bin/sh",
            #     )
            # )

            # while response.is_open():
            #     response.update(timeout=1)
            # if response.peek_stdout():
            #     print(f"STDOUT: {response.read_stdout()}")
            # if response.peek_stderr():
            #     print(f"STDERR: {response.read_stderr()}")
            # if commands:
            #     c = commands.pop(0)
            #     print(f"Running command... {c}\n")
            #     response.write_stdin(c + "\n")
            # else:
            #     break

        # Scale the controller back up
        if controller_name is not None:
            modify_controller_replicas(
                controller_name,
                controller_namespace,
                controller_kind,
                previous_replicas,
            )


def render_job(job_name: str, args=None):
    # Check if a file in settings.JOBS_DIR exists with the given job name
    jobs_dir = config.get_full_atils_dir("JOBS_DIR")
    if os.path.exists(os.path.join(jobs_dir, job_name, "job.yaml")):
        rendered_job = template_utils.template_external_file(
            os.path.join(jobs_dir, job_name, "job.yaml"), args
        )
        return yaml.safe_load(rendered_job)

    else:
        logging.error(f'Job "{job_name}" was not found')
        exit(1)


def launch_job(job_dict):
    name_field = job_dict["metadata"]["name"]

    if "namespace" in job_dict["metadata"]:
        namespace = job_dict["metadata"]["namespace"]
    else:
        _, active_context = k8s_config.list_kube_config_contexts()
        if "namespace" in active_context["context"]:
            namespace = active_context["context"]["namespace"]
        else:
            namespace = "default"
        job_dict["metadata"]["namespace"] = namespace

    clear_job_name(name_field, namespace)

    k8s_client = client.ApiClient()
    utils.create_from_dict(k8s_client, job_dict)


def clear_job_name(name_field: str, namespace: str):
    # Check if a job with a name matching the given job name already exists, and delete if so
    v1 = client.BatchV1Api()
    for job in v1.list_namespaced_job(namespace).items:
        if job.metadata.name == name_field:
            # TODO Let's also delete all pods associated with the job
            v1.delete_namespaced_job(name=name_field, namespace=namespace)
            # Wait until the job is deleted
            dots = itertools.cycle([".  ", ".. ", "..."])
            spinner = itertools.cycle(["-", "\\", "|", "/"])

            job = v1.read_namespaced_job(name=name_field, namespace=namespace)
            while job:
                try:
                    job = v1.read_namespaced_job(name=name_field, namespace=namespace)
                    print(
                        f"Waiting for job {name_field} to be deleted{next(dots)} {next(spinner)}",
                        end="\r",
                    )
                    time.sleep(0.2)
                except client.rest.ApiException as e:
                    if e.status == 404:
                        job = None
                    else:
                        raise e
            print("\n")
            logging.info(f"Job {name_field} deleted")
            break


def run_job_cli(job_name: str, args=None):
    rendered_job = render_job(job_name, args)
    launch_job(rendered_job)
    logging.info(f"Job {job_name} created")
