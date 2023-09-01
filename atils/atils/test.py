import os
import json
import yaml
import subprocess
import tempfile
import argparse

from atils.common import config


def main(args: str):
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(
        help="Select a subcommand", dest="subparser_name"
    )

    create_parser = subparsers.add_parser(
        "create",
        help="Create the setup for a test environment. A test\
            env is a docker compose, plus commands or containers that can be run with different parameters",
    )
    create_parser.add_argument(
        "env_name", help="The name of the environment that has a setup we want to test"
    )
    create_parser.add_argument(
        "-d", "--directory", help="What directory to create the test environment in."
    )

    args = parser.parse_args(args)

    if args.subparser_name == "create":
        if args.directory is not None:
            create_test_env(args.env_name, args.directory)
        else:
            create_test_env(args.env_name)


def create_test_env(env_name: str, basedir: str = config.TEST_ENVIRONMENTS_DIR):
    # Check if basedir exists, if not, create it
    if not os.path.exists(basedir):
        os.makedirs(basedir)

    # Check if a directory named env_name exists in basedir
    env_dir = os.path.join(basedir, env_name)
    if not os.path.exists(env_dir):
        os.makedirs(env_dir)

    # Look for env_name_definition.yml in env_name directory
    definition_file = os.path.join(env_dir, f"{env_name}_definition.yml")
    if not os.path.exists(definition_file):
        # Open a default editor window for the user to edit the file
        with open(definition_file, "w") as f:
            subprocess.run([os.getenv("EDITOR", "vi"), f.name])

    # Check if env_name_tests.json exists
    tests_file = os.path.join(env_dir, f"{env_name}_tests.json")
    if not os.path.exists(tests_file):
        tests = []
        while True:
            create_new_test = input("Would you like to create a new test? (yes/no): ")
            if create_new_test.lower() != "yes":
                break
            test_name = input("Enter the name of the test: ")
            test_command = input("Enter the command to run for the test: ")
            test = {"testname": test_name, "command": test_command}
            tests.append(test)

        # Save the list of tests as a JSON object
        with open(tests_file, "w") as f:
            json.dump(tests, f, indent=4)
