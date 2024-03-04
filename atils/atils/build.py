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
        help="A single action set defined in .atils_buildconfig.json of current directory to run",
    )

    arguments: argparse.Namespace = parser.parse_args(args)

    directory: str = os.getcwd()
    show_actions: bool = True
    show_action_sets: bool = True

    if arguments.actions_only:
        show_actions = False
    if arguments.action_sets_only:
        show_action_sets = False

    if not show_actions and not show_action_sets:
        raise ValueError("You need to allow showing either actions or action sets")

    if arguments.build_directory is not None:
        directory = arguments.build_directory

    if arguments.action == "list":
        run_list_action(directory, show_actions, show_action_sets)
    else:
        if arguments.actions is not None:
            run_build_actions(arguments.actions, directory)
        elif arguments.action_set is not None:
            run_build_action_set(arguments.action_set, directory)
        else:
            default_action_set: str = _get_default_action_set(directory)
            if default_action_set:
                run_build_action_set(default_action_set, directory)
            else:
                logging.error(
                    "No default action set defined. Either define one in"
                    + f" {os.path.join(directory, '.atils_buildconfig.json')} or use an argument to specify what to do"
                )


def validate_listed_actions(
    available_actions: list[dict], listed_actions: list[str]
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
            _print_action_set(action_set, available_actions)


def run_build_action_set(action_set_name: str, directory: str) -> None:
    """
    Runs all the actions defined in a given action_set
    Args:
        action_set (dict): A dictionary representing an action set
        directory (str): The directory where our .atils_buildconfig.json file to list is located
    """
    available_actions: list[dict] = _get_available_actions(directory)
    action_set: dict = _get_action_set(action_set_name, directory)

    validate_listed_actions(available_actions, action_set["actions"])

    if "strict" in action_set and not action_set["strict"]:
        for action in available_actions:
            if action["name"] in action_set["actions"]:
                _run_action(action, directory)
    else:
        for action in available_actions:
            if action["name"] in action_set["actions"]:
                _run_action_strict(action, directory)


def run_build_actions(listed_actions: list[str], directory: str) -> None:
    # TODO cd to a directory, if one is specified
    # TODO allow us to mark if all build actions must pass
    """
    Run user-specified build actions, in the order specified by .atils_buildconfig.json.
    Args:
        listed_actions (list[str]): The list of actions provided by the user.
        directory (str): The directory to use as the current working directory.
    """
    available_actions = _get_available_actions(directory)

    validate_listed_actions(available_actions, listed_actions)

    if "all" in listed_actions:
        for action in available_actions:
            _run_action(action, directory)
    else:
        # Since I know you might ask... we do it this way to ensure that the actions are run in order.
        # The user can enter them arbitrarily, but available_actions is sorted, so we can use that as
        # our source of truth
        for action in available_actions:
            if action["name"] in listed_actions:
                _run_action(action, directory)


def _get_available_actions(directory: str) -> list[dict]:
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


def _get_available_action_sets(directory: str) -> list[dict]:
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
            return sorted(data["action_sets"], key=lambda x: x["name"])
    else:
        raise FileNotFoundError(f"{filename} does not exist")


def _get_action_set(action_set: str, directory: str) -> dict:
    """
    Get a given action set from an .atils_buildconfig.json file
    Args:
        action_set (str): The name of the action set to get
        directory (str): The directory where the .atils_buildconfig.json file is located
    Returns:
        A dictionary representing the action set, or an empty dictionary if the action set is not found
    """
    available_action_sets = _get_available_action_sets(directory)

    for action_set_obj in available_action_sets:
        if action_set_obj["name"] == action_set:
            return action_set_obj
    raise ValueError(
        f"Action set {action_set} not available in {os.path.join(directory, '.atils_buildconfig.json')}"
    )


def _get_default_action_set(directory: str) -> str:
    """
    Given a directory with an .atils_buildconfig.json file, return the name of the default action set.
    Args:
        directory (str): The directory where the .atils_buildconfig.json file is located
    Returns:
        A string representing the name of the default action set, or an empty string if no default action set is found.
    """
    available_action_sets: list[dict] = _get_available_action_sets(directory)
    for action_set in available_action_sets:
        if "default" in action_set and action_set["default"]:
            return action_set["name"]
    return ""


def _print_action(action: dict) -> None:
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


def _print_action_set(action_set: dict, actions: list[dict]) -> None:
    """
    Print the name and actions of an action set.
    Args:
        action_set (dict): An object representing an action set from a .atils_buildconfig.json file.
        actions (list[dict]): A list of objects, representing all available actions
    """
    print(f"{action_set['name']}:")
    if "description" in action_set:
        print(f"  {action_set['description']}")
    print(action_set)
    for action in action_set["actions"]:
        if "description" in actions[action]:
            print(f"  {action} | {actions[action]['description']}")
        else:
            print(f"  {action} | {actions[action]['command']}")
    print()


def _run_action(action: dict, directory: str) -> None:
    """
    Run the command from an action, using subprocess.run
    Args:
        action (object): An object representing an action
    """

    subprocess.run(action["command"], shell=True, cwd=directory)


def _run_action_strict(action: dict, directory: str) -> None:
    """
    Run the command from an action, using subprocess.run. Fails if the command fails
    Args:
        action (object): An object representing an action
    """
    try:
        subprocess.run(action["command"], shell=True, cwd=directory, check=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"Error running {action['name']}")
        exit(1)
