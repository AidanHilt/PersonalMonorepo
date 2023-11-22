import argparse
import logging
import os
import subprocess
import sys

import watchfiles

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

    auto_deploy_parser.add_argument(
        "--chart-name",
        "-cn",
        type=str,
        help="The name of the helm chart to watch",
        required=True,
    )

    if len(args) == 0:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args(args)

    if args.subparser_name == "auto-deploy":
        auto_deploy_helm_chart(args.chart_name)


def auto_deploy_helm_chart(chart_name: str):
    helm_chart_dir = os.path.join(
        settings.install_dir, settings.helm_charts_dir, chart_name
    )

    watchfiles.main.logger.setLevel(logging.WARNING)

    # Check if there is a directory at the given path, that has a Chart.yaml file in it
    if os.path.isdir(helm_chart_dir) and os.path.isfile(
        os.path.join(helm_chart_dir, "Chart.yaml")
    ):
        logging.info(f"Watching for file changes in {helm_chart_dir}")
        for change in watchfiles.watch(helm_chart_dir):
            print(change)
            values_file = os.path.join(
                settings.config_directory, "helm-values", f"{chart_name}.yaml"
            )
            if os.path.isfile(values_file):
                subprocess.run(
                    [
                        "helm",
                        "upgrade",
                        "--install",
                        chart_name,
                        helm_chart_dir,
                        "-f",
                        values_file,
                    ]
                )
            else:
                subprocess.run(
                    ["helm", "upgrade", "--install", chart_name, helm_chart_dir]
                )
    else:
        logging.error(f"No chart found at the given path: {helm_chart_dir}")
        exit(1)
