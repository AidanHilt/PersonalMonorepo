import argparse
import json
import logging
import os
import subprocess

from atils.common import config

logging.basicConfig(level=config.get_logging_level())  # type: ignore


def main(args: list[str]):
    parser: argparse.ArgumentParser = argparse.ArgumentParser()

    parser.add_argument(
        "action",
        help="Select which action to perform. Defaults to build",
        default="build",
        nargs="?",
    )

    parser.add_argument(
        "--build-directory",
        "-bd",
        type=str,
        help="The directory where .atils_buildconfig.json is located",
    )

    parser.add_argument(
        "--actions-only", "-ao", help="Only show actions", action="store_true"
    )
    parser.add_argument(
        "--action-sets-only", "-aso", help="Only show action sets", action="store_true"
    )

    parser.add_argument(
        "--actions",
        nargs="*",
        help="Actions defined in .atils_buildconfig.json of current directory to run",
    )

    parser.add_argument(
        "--action-set",
        nargs="*",
        help="A single action set defined in .atils_buildconfig.json of current directory to run",
    )

    args = parser.parse_args(args)

    directory: str = os.getcwd()
    show_actions: bool = True
    show_action_sets: bool = True

    if args.actions_only:
        show_actions = False
    if args.action_sets_only:
        show_action_sets = False

    if not show_actions and not show_action_sets:
        raise ValueError("You need to allow showing either actions or action sets")

    if args.build_directory is not None:
        directory = args.build_directory

    if args.action == "list":
        run_list_action(directory, show_actions, show_action_sets)
    else:
        run_build_actions(args, directory)


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


def run_list_action(directory: str, show_actions: bool, show_action_sets: bool) -> None:
    """
    List all available build actions, or only actions or only action sets.
    Args:
        directory (str): The directory where our .atils_buildconfig.json file to list is located
        show_actions (bool): Whether to show actions or not
        show_action_sets (bool): Whether to show action sets or not
    Raises:
        ValueError: If both show_actions and show_action_sets are True.
    Returns:
        None
    """
    available_actions = _get_available_actions(directory)
    available_action_sets = _get_available_action_sets(directory)

    if not show_actions and not show_action_sets:
        raise ValueError("Cannot specify both actions_only and action_sets_only")
    if show_actions:
        print("Actions")
        print("=======================================")
        for action in available_actions:
            _print_action(action)
    if show_action_sets:
        print("Action Sets")
        print("=======================================")
        for action_set in available_action_sets:
            _print_action_set(action_set)


def run_build_actions(args: object, directory: str) -> None:
    # TODO cd to a directory, if one is specified
    # TODO allow us to mark if all build actions must pass
    """
    Run user-specified build actions, in the order specified by .atils_buildconfig.json.
    Args:
        actions (): The list of actions provided by the user. TODO figure out what the shape of the object is,
        so we can document it here
    """
    listed_actions = args.actions
    if listed_actions is None:
        listed_actions = ["all"]
    available_actions = _get_available_actions(directory)

    validate_listed_actions(available_actions, listed_actions)

    if "all" in listed_actions:
        for action in available_actions:
            run_action(action)
    else:
        # Since I know you might ask... we do it this way to ensure that the actions are run in order.
        # The user can enter them arbitrarily, but available_actions is sorted, so we can use that as
        # our source of truth
        for action in available_actions:
            if action["name"] in listed_actions:
                run_action(action)


def _get_available_actions(directory: str) -> list[object]:
    """
    List all actions available in a .atils_buildconfig.json file in the given directory.
    The file must be in the given directory and must be a valid JSON file.
    The file must contain a list of actions, each action must be an object with the following keys:
        - name: The name of the action
        - command: The command to run
        - order: The order in which to run the action. Lower numbers are run first.
    The actions are returned sorted by their order.
    Arguments:
        directory (str): The directory where the .atils_buildconfig.json file is located.
    Returns:
        A list of objects representing actions available in the .atils_buildconfig.json file.
    """
    filename: str = os.path.join(directory, ".atils_buildconfig.json")

    if os.path.isfile(filename):
        with open(filename) as f:
            data = json.load(f)
            if "actions" not in data:
                raise ValueError(f"No actions found in {filename}")
            return sorted(data["actions"], key=lambda x: x["order"])
    else:
        raise FileNotFoundError(f"{filename} does not exist")


def _get_available_action_sets(directory: str) -> list[object]:
    """
    List all action sets available in a .atils_buildconfig.json file in the given directory.
    The file must be in the given directory and must be a valid JSON file.
    The file must contain a list of action sets, each action set must be an object with the following keys:
        - name: The name of the action set
        - actions: A list of actions in the action set
    The action sets are returned sorted by their name.
    Arguments:
        directory (str): The directory where the .atils_buildconfig.json file is located.
    Returns:
        A list of objects representing action sets available in the .atils_buildconfig.json file. Returns an empty
        list if no such list is found
    """
    filename = os.path.join(directory, ".atils_buildconfig.json")

    if os.path.isfile(filename):
        with open(filename) as f:
            data = json.load(f)
            if "action_sets" not in data:
                return []
            return sorted(data.action_sets, key=lambda x: x["name"])
    else:
        raise FileNotFoundError(f"{filename} does not exist")


def _print_action(action: object) -> None:
    """
    Print the name and command of an action.
    Args:
        action (object): An object representing an action from a .atils_buildconfig.json file.
    """
    if "description" in action:
        print(f"{action['name']}: {action['command']} | {action['description']}")
    else:
        print(f"{action['name']}: {action['command']}")
    print()


def _print_action_set(action_set: object, actions: list[object]) -> None:
    """
    Print the name and actions of an action set.
    Args:
        action_set (object): An object representing an action set from a .atils_buildconfig.json file.
        actions (list[object]): A list of objects, representing all available actions
    """
    print(f"{action_set['name']}:")
    if "description" in action_set:
        print(f"  {action_set['description']}")
    for action in action_set["actions"]:
        if "description" in actions[action]:
            print(f"  {action} | {actions[action]['description']}")
        else:
            print(f"  {action} | {actions[action]['command']}")
    print()
