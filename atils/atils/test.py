import argparse
import inspect
import logging
import sys
import termios
import tty
from threading import Thread

from kubernetes.stream import stream

from atils.common import config
from kubernetes import client
from kubernetes import config as k8s_config

logging.basicConfig(level=config.get_logging_level())  # type: ignore


# ==========================================
# Stuff for actually running test functions
# ==========================================
def main(args: str):
    parser: argparse.ArgumentParser = argparse.ArgumentParser()

    parser.add_argument(
        "action",
        help="Select which action to perform. Defaults to build",
        default="run",
        nargs="?",
    )

    parser.add_argument("--function-name", type=str)

    arguments: argparse.Namespace = parser.parse_args(args)

    if arguments.action == "run":
        if arguments.function_name is None:
            logging.error("No function name specified")
            exit(1)
        else:
            function = globals().get(arguments.function_name)
            if function is None:
                logging.error(f"Function {arguments.function_name} not found")
                exit(1)
            else:
                function()
    elif arguments.action == "list":
        functions = _get_function_list()
        if len(functions) == 0:
            print("There are no test functions here at the moment")
            exit(0)
        for function in functions:
            print(function)
    else:
        logging.error(
            "Invalid action. If you are trying to run a specific function, remember to use --function-name"
        )


def _get_function_list():
    function_list = []
    for name, obj in inspect.getmembers(inspect.getmodule(inspect.currentframe())):
        if inspect.isfunction(obj) and not name.startswith("_") and name != "main":
            function_list.append(name)
    return function_list


# =======================
# Functions being tested
# =======================


# redirect input
def _read(resp):
    # resp.write_stdin("stty rows 45 cols 130\n")
    while resp.is_open():
        char = sys.stdin.read(1)
        resp.update()
        if resp.is_open():
            resp.write_stdin(char)


def patch_pod_with_debug_container(name: str, namespace: str):
    return


def exec_shell_in_pod(
    name: str = "argocd-application-controller-0", namespace="argocd"
):
    k8s_config.load_kube_config()
    api_client = client.ApiClient()
    api_instance = client.CoreV1Api(api_client)

    exec_command = ["/bin/bash"]

    resp = stream(
        api_instance.connect_get_namespaced_pod_exec,
        name,
        namespace,
        command=exec_command,
        stderr=True,
        stdin=True,
        stdout=True,
        tty=True,
        _preload_content=False,
    )

    t = Thread(target=_read, args=[resp])

    # change tty mode to be able to work with escape characters
    stdin_fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(stdin_fd)
    try:
        tty.setraw(stdin_fd)
        t.start()
        while resp.is_open():
            data = resp.read_stdout(10)
            if resp.is_open():
                if len(data or "") > 0:
                    sys.stdout.write(data)
                    sys.stdout.flush()
    finally:
        # reset tty
        print("\033c")
        termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_settings)
        print("press enter")
