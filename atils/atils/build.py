import argparse
import json
import logging
import os
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
    filename = ".atils\_buildconfig.json"

    if os.path.isfile(filename):
        with open(filename) as f:
            data = json.load(f)
            return data
    else:
        raise FileNotFoundError(f"{filename} does not exist")


def run_build_actions(actions):
    print(get_available_build_actions())
    for action in actions[0][1]:
        print(action)
