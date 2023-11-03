import argparse
import logging
import sys

from atils.common import config, template_utils
from atils.common.settings import settings

logging.basicConfig(level=config.get_logging_level())  # type: ignore


def main(args: str):
    parser: argparse.ArgumentParser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(
        help="Select a subcommand", dest="subparser_name"
    )

    auto_deploy_parser = subparsers.add_parser(
        "auto-deploy", help="Watch a helm chart for changes, and deploy automatically"
    )

    if len(args) == 0:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args(args)

    if args.subparser_name == "init":
        initialize_kustomize_template()
