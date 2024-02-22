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

    # TODO Add a subcommand to list valid build actions
    # TODO Add an argument to specify the directory where the .atils_buildconfig.json file is located.

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
    """
    List all actions available in a .atils_buildconfig.json file in the current directory.
    The file must be in the current directory and must be a valid JSON file.
    The file must contain a list of actions, each action must be a dictionary with the following keys:
        - name: The name of the action
        - command: The command to run
        - order: The order in which to run the action. Lower numbers are run first.
    The actions are sorted by their order.
    Returns:
        A list of objects representing actions available in the .atils_buildconfig.json file.
    """
    filename = os.path.join(os.getcwd(), ".atils_buildconfig.json")

    if os.path.isfile(filename):
        with open(filename) as f:
            data = json.load(f)
            return sorted(data, key=lambda x: x["order"])
    else:
        raise FileNotFoundError(f"{filename} does not exist")


def validate_listed_actions(
    available_actions: list[object], listed_actions: list[str]
) -> None:
    """
    Takes a list of valid actions, a list of actions provided by a user, and ensures that all
    actions provided by the user are valid.
    Args:
        available_actions (list[object]): A list of objects representing available actions.
        listed_actions (list[str]): A list of strings representing actions provided by the user.
    Raises:
        ValueError: If any action provided by the user is not valid.
    Returns:
        None.
    """
    available_action_names = [action["name"] for action in available_actions]
    for action in listed_actions:
        if action not in available_action_names and action != "all":
            raise ValueError(f"{action} is not a valid action")


def run_action(action: object) -> None:
    """
    Run the command from an action, using subprocess.run
    Args:
        action (object): An object representing an action
    """
    subprocess.run(action["command"], shell=True)


def run_build_actions(actions) -> None:
    """
    Run user-specified build actions, in the order specified by .atils_buildconfig.json.
    Args:
        actions (): The list of actions provided by the user. TODO figure out what the shape of the object is,
        so we can document it here
    """
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
