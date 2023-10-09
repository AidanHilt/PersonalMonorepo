import argparse
import itertools
import logging
import os
import time

import yaml

from atils.common import config, template_utils
from atils.common.settings import settings
from kubernetes import client
from kubernetes import config as k8s_config
from kubernetes import dynamic, utils

k8s_config.load_kube_config()  # type: ignore
client.rest.logger.setLevel(logging.WARNING)

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

    args = parser.parse_args(args)

    if args.subparser_name == "run":
        job_args = {}

        args_dict = vars(args)
        if "image" in args_dict and args_dict["image"] is not None:
            job_args["image_tag"] = args_dict["image"]
        else:
            job_args["image_tag"] = "latest"

        run_job(args.job_name, job_args)


def run_job(job_name: str, args: list[str] = None):
    # Check if a file in settings.JOBS_DIR exists with the given job name
    jobs_dir = config.get_full_atils_dir("JOBS_DIR")
    if os.path.exists(os.path.join(jobs_dir, job_name + ".yaml")):
        rendered_job = template_utils.template_external_file(
            os.path.join(jobs_dir, job_name + ".yaml"), args
        )
        job_dict = yaml.safe_load(rendered_job)

        name_field = job_dict["metadata"]["name"]

        if "namespace" in job_dict["metadata"]:
            namespace = job_dict["metadata"]["namespace"]
        else:
            _, active_context = k8s_config.list_kube_config_contexts()
            print(active_context)
            if "namespace" in active_context["context"]:
                namespace = active_context["context"][namespace]
            else:
                namespace = "default"

        # Check if a job with a name matching the given job name already exists, and delete if so
        v1 = client.BatchV1Api()
        for job in v1.list_namespaced_job(namespace).items:
            print(job.metadata.name)
            if job.metadata.name == name_field:
                v1.delete_namespaced_job(name=name_field, namespace=namespace)
                # Wait until the job is deleted
                dots = itertools.cycle([".  ", ".. ", "..."])
                spinner = itertools.cycle(["-", "\\", "|", "/"])

                job = v1.read_namespaced_job(name=name_field, namespace=namespace)
                while job:
                    try:
                        job = v1.read_namespaced_job(
                            name=name_field, namespace=namespace
                        )
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

        k8s_client = client.ApiClient()
        utils.create_from_dict(k8s_client, job_dict)
        logging.info(f"Job {name_field} created")

    else:
        logging.error(f'Job "{job_name}" was not found')
        exit(1)
