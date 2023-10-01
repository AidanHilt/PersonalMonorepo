import logging
import os
import argparse
import sys
import tempfile
import subprocess
import yaml

from atils.common import config
from atils.common import template_utils as template
from atils.common import yaml_utils

logging.basicConfig(config.get_logging_level())  # type: ignore


def main(args: str):
    parser: argparse.ArgumentParser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(
        help="Select a subcommand", dest="subparser_name"
    )

    init_parser = subparsers.add_parser(
        "init",
        help="Initialize a new Kustomize template, with pre-populated environments",
    )

    if len(args) == 0:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args(args)

    if args.subparser_name == "init":
        initialize_kustomize_template()


def create_directory_structure(template_name: str):
    if not os.path.exists(template_name):
        os.makedirs(template_name)

    base_dir = os.path.join(template_name, "base")
    overlays_dir = os.path.join(template_name, "overlays")
    if not os.path.exists(base_dir):
        os.makedirs(base_dir)
    if not os.path.exists(overlays_dir):
        os.makedirs(overlays_dir)

    prod_dir = os.path.join(overlays_dir, "prod-cluster")
    dev_vms_dir = os.path.join(overlays_dir, "dev-cluster")
    dev_laptop_dir = os.path.join(overlays_dir, "dev-laptop")
    if not os.path.exists(prod_dir):
        os.makedirs(prod_dir)
    if not os.path.exists(dev_vms_dir):
        os.makedirs(dev_vms_dir)
    if not os.path.exists(dev_laptop_dir):
        os.makedirs(dev_laptop_dir)


def read_new_base_files() -> dict[str, str]:
    files_and_content = {}
    while True:
        user_choice = input("Would you like to create a new base file? (yes/no): ")

        if user_choice.lower() == "yes":
            file_name = input("Enter the name of the file: ")

            # Add .yaml extension if file does not have an extension
            if not os.path.splitext(file_name)[1]:
                file_name += ".yaml"

            edit_choice = input("Would you like to edit the file? (yes/no): ")

            if edit_choice.lower() == "yes":
                # Open the default console text editor to edit the file
                with tempfile.NamedTemporaryFile(
                    suffix=".yaml", delete=False
                ) as temp_file:
                    temp_file.close()
                    subprocess.call([os.environ.get("EDITOR", "vi"), temp_file.name])

                    # Read the edited content from the file
                    with open(temp_file.name, "r") as edited_file:
                        edited_content = edited_file.read()

                    # Create a dictionary with the file name as the key and the edited content as the value
                    files_and_content[file_name] = edited_content

                    os.remove(temp_file.name)
            else:
                files_and_content[file_name] = ""

            continue
        else:
            return files_and_content


def create_base_files(directory: str, file_list: dict[str, str]):
    base_dir = os.path.join(directory, "base")
    overlays_dir = os.path.join(directory, "overlays")

    for filename in file_list.keys():
        file_path = os.path.join(base_dir, filename)

        with open(file_path, "w") as file:
            file.write(file_list[filename])

        for subdir in os.listdir(overlays_dir):
            subdir_path = os.path.join(overlays_dir, subdir)
            if os.path.isdir(subdir_path):
                for filename in file_list.keys():
                    file_path = os.path.join(subdir_path, filename)

                    with open(file_path, "w") as file:
                        file.write(file_list[filename])


def add_resources_to_kustomization_files(directory: str, file_list: dict[str, str]):
    base_dir = os.path.join(directory, "base")
    overlays_dir = os.path.join(directory, "overlays")

    kustomization = yaml_utils.convert_yaml_to_dict(
        os.path.join(base_dir, "kustomization.yaml")
    )
    kustomization["resources"] = list(file_list.keys())

    with open(os.path.join(base_dir, "kustomization.yaml"), "w") as file:
        yaml.dump(kustomization, file)

    for subdir in os.listdir(overlays_dir):
        kustomization = yaml_utils.convert_yaml_to_dict(
            os.path.join(overlays_dir, subdir, "kustomization.yaml")
        )
        kustomization["patchesStrategicMerge"] = list(file_list.keys())

        with open(
            os.path.join(overlays_dir, subdir, "kustomization.yaml"), "w"
        ) as file:
            yaml.dump(kustomization, file)


def initialize_kustomize_template():
    template_name = input("Enter the name of the template: ")

    files_and_content = read_new_base_files()

    create_directory_structure(template_name)

    template.template_file_and_output(
        "../templates/kustomization-base.yaml",
        os.path.join(template_name, "base/kustomization.yaml"),
    )
    overlays_dir = os.path.join(template_name, "overlays")
    for subdir in os.listdir(overlays_dir):
        subdir_path = os.path.join(overlays_dir, subdir)
        if os.path.isdir(subdir_path):
            template.template_file(
                "../templates/kustomization-overlay.yaml",
                os.path.join(overlays_dir, subdir, "kustomization.yaml"),
            )

    create_base_files(template_name, files_and_content)
    add_resources_to_kustomization_files(template_name, files_and_content)

    print("Kustomize template initialized successfully.")
