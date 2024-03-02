import argparse
import asyncio
import logging
import os
import subprocess
import sys
import time

import watchfiles

from atils.common import config
from atils.common.settings import settings

logging.basicConfig(level=config.get_logging_level())  # type: ignore
logging.getLogger("asyncio").setLevel(logging.WARNING)
watchfiles.main.logger.setLevel(logging.WARNING)


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

    arguments: argparse.Namespace = parser.parse_args(args)

    # Let's explain this a little bit. We run the auto_deploy_helm_chart async, so that when we get a
    # KeyboardInterrupt (i.e. Ctrl+C ), we can uninstall the chart automatically.
    if arguments.subparser_name == "auto-deploy":
        try:
            asyncio.run(auto_deploy_helm_chart(arguments.chart_name))
        except KeyboardInterrupt:
            subprocess.run(["helm", "uninstall", arguments.chart_name])


async def auto_deploy_helm_chart(chart_name: str) -> None:
    """
    Automatically deploy a helm chart in the HELM_CHARTS_DIR directory. After the initial deployment,
    it then reinstalls the chart whenever an update is made to the chart, or to the values file located at
    ~/.atils/helm-values/<chart-name>.yaml

    Args:
        chart_name (str): The name of the helm chart to deploy.
    """
    helm_chart_dir = os.path.join(
        settings.install_dir, settings.helm_charts_dir, chart_name
    )

    # Check if there is a directory at the given path, that has a Chart.yaml file in it
    if os.path.isdir(helm_chart_dir) and os.path.isfile(
        os.path.join(helm_chart_dir, "Chart.yaml")
    ):
        print(f"Watching and auto-installing {chart_name}...")
        _install_helm_chart(chart_name, helm_chart_dir)
        # This is where we watch for changes to the chart and values file. Those specific functions then
        # handle calling the install function
        await asyncio.gather(
            _watch_chart_path(chart_name), _watch_values_path(chart_name)
        )

    else:
        logging.error(f"No chart found at the given path: {helm_chart_dir}")
        exit(1)


def _install_helm_chart(chart_name: str, helm_chart_dir: str) -> None:
    """
    Automatically installs a helm chart located at helm_chart_dir. If there is a file at
    ~/.atils/helm-values/<chart_name>.yaml, this functions uses that as the values.yaml file

    Args:
        chart_name (str): The name of the helm chart to install, which is used as the release name
        helm_chart_dir (str): The path to the helm chart to install
    """
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
        subprocess.run(["helm", "upgrade", "--install", chart_name, helm_chart_dir])


async def _watch_chart_path(chart_name: str) -> None:
    """
    Watches a local helm chart for changes, and calls _install_helm_chart whenever an update is detected

    Args:
        chart_name (str): The name of the chart. This will be the name of a directory in the HELM_CHARTS_DIR
    """
    helm_chart_dir = os.path.join(
        settings.install_dir, settings.helm_charts_dir, chart_name
    )

    async for change in watchfiles.awatch(helm_chart_dir):
        _install_helm_chart(chart_name, helm_chart_dir)


async def _watch_values_path(chart_name: str) -> None:
    """
    Watches the values file in ~/.atils/helm-values/<chart_name>.yaml for changes, and calls _install_helm_chart
    whenever an update is detected

    Args:
        chart_name (str): The name of the chart. This will be the name of a directory in the HELM_CHARTS_DIR
    """
    helm_chart_dir = os.path.join(
        settings.install_dir, settings.helm_charts_dir, chart_name
    )

    values_file = os.path.join(
        settings.config_directory, "helm-values", f"{chart_name}.yaml"
    )
    # TODO we may want to clean this up, I don't think we need to loop in this function, when we're calling it in a loop
    while True:
        if os.path.isfile(values_file):
            async for change in watchfiles.awatch(values_file):
                _install_helm_chart(chart_name, helm_chart_dir)
        else:
            time.sleep(5)
