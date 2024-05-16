import argparse
import inspect
import logging

from atils.common import config

logging.basicConfig(level=config.get_logging_level())  # type: ignore


# ==========================================
# Stuff for actually running test functions
# ==========================================
def main(args: str):
    parser: argparse.ArgumentParser = argparse.ArgumentParser()

    parser.add_argument(
        "action",
        help="Select which action to perform. Defaults to run",
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
