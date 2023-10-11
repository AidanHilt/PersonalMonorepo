import argparse
import logging
import os
import sys

from atils.common import config, settings
from atils.common.settings import settings

logging.basicConfig(level=config.get_logging_level())  # type: ignore


# TODO Figure out how to do this correctly
def call_pytest(path: str):
    os.system(f"python3 -m pytest {path}")


def call_mypy(path: str):
    os.system(f"python3 -m mypy {path}")


def main(args: str):
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(
        help="Select a subcommand", dest="subparser_name"
    )

    # TODO Let's set a standard for how optional arguments are handled
    test_parser = subparsers.add_parser("test", help="Run pytest against the project")
    test_parser.add_argument(
        "python_dir", nargs="?", default=f"{settings.SCRIPT_INSTALL_DIRECTORY}/tests"
    )

    type_parser = subparsers.add_parser("type-check", help="Run the mypy type checker")
    type_parser.add_argument(
        "python_dir", nargs="?", default=f"{settings.SCRIPT_INSTALL_DIRECTORY}/atils"
    )

    if len(args) == 0:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args(args)

    if args.subparser_name == "test":
        call_pytest(args.python_dir)
    elif args.subparser_name == "type-check":
        call_mypy(args.python_dir)
