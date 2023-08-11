import json
import os

# TODO Make this more universal, but this is a good spot to store it for now
SCRIPT_INSTALL_DIRECTORY = "/Users/ahilt/PersonalMonorepo/atils"
KUBECONFIG_LOCATION = "/Users/ahilt/.kube/"


def get_commands_list(command_config: str) -> list[tuple[str, str, str]]:
    COMMAND_CONFIGURATION: str = os.path.join(
        SCRIPT_INSTALL_DIRECTORY,
        f"atils/command-configurations/{command_config}.json",
    )

    commands: list[tuple[str, str, str]] = read_commands_from_file(
        COMMAND_CONFIGURATION
    )

    return commands


def get_command_executor(command_config: str, command: str) -> str:
    COMMAND_CONFIGURATION: str = os.path.join(
        SCRIPT_INSTALL_DIRECTORY,
        f"atils/command-configurations/{command_config}.json",
    )

    commands: list[tuple[str, str, str]] = read_commands_from_file(
        COMMAND_CONFIGURATION
    )

    if any(command == tpl[0] for tpl in commands):

        command_info: tuple[str, str, str] = next(
            (tpl for tpl in commands if tpl[0] == command)
        )

        # TODO Please, dear god, tell me there's a better way to do this
        val: str = command_info[1].replace(
            r"${config.SCRIPT_INSTALL_DIRECTORY}", SCRIPT_INSTALL_DIRECTORY
        )

        return val

    else:
        print(
            f"Sorry, {command} is not a valid subcomand for the {command_config} utility"
        )
        exit(1)


def read_commands_from_file(file_path: str) -> list[tuple[str, str, str]]:
    if os.path.exists(file_path):
        with open(file_path, "r") as f:
            commands_data: list[dict[str, str]] = json.load(f)

        commands_list: list[tuple[str, str, str]] = []
        for command in commands_data:
            commands_list.append(
                (
                    command["command-name"],
                    command["command-executor"],
                    command["description"],
                )
            )

        return commands_list
    else:
        print(
            f"File path '{file_path}' not found. This is an error in internal configuration. Aborting"
        )
        exit(1)
