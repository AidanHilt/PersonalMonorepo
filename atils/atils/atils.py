import os
import sys

from atils import config

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Atils requires at least one subcommand argument.")
        sys.exit(1)

    script_name: str = sys.argv[1]
    command_executor = config.get_command_executor("atils", script_name)

    # TODO Let's make the error handling on this cleaner, right now we don't actually check that
    # the command to run can run
    subprocess_args: str = " ".join([command_executor] + sys.argv[2:])
    os.system(subprocess_args)
