import argparse
import json
import logging
import os
import subprocess
import sys

from atils.common import config

logging.basicConfig(level=config.get_logging_level())  # type: ignore


def main(args: list[str]):
    parser: argparse.ArgumentParser = argparse.ArgumentParser()

    parser.add_argument(
        "actions",
        nargs="*",
        help="Actions defined in .atils_buildconfig.json of current directory",
    )

    if len(args) == 0:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args(args)

    run_build_actions(args._get_kwargs())


def get_available_build_actions() -> list[object]:
    filename = os.path.join(os.getcwd(), ".atils_buildconfig.json")

    if os.path.isfile(filename):
        with open(filename) as f:
            data = json.load(f)
            return sorted(data, key=lambda x: x["order"])
    else:
        raise FileNotFoundError(f"{filename} does not exist")


def validate_listed_actions(available_actions: list[object], listed_actions: list[str]):
    available_action_names = [action["name"] for action in available_actions]
    for action in listed_actions:
        if action not in available_action_names and action != "all":
            raise ValueError(f"{action} is not a valid action")


def run_action(action: object):
    subprocess.run(action["command"], shell=True)


def run_build_actions(actions):
    listed_actions = actions[0][1]
    available_actions = get_available_build_actions()

    validate_listed_actions(available_actions, listed_actions)

    if "all" in listed_actions:
        for action in available_actions:
            run_action(action)
    else:
        for action in available_actions:
            if action["name"] in listed_actions:
                run_action(action)
