from rich.align import Align
from rich.console import Console
from rich.table import Table


def print_jobconfig(jobconfig_data: dict) -> None:
    """
    Given a jobconfig dictionary, print it to the console as a table

    Args:
        jobconfig_data (dict): The jobconfig dictionary representation
    """
    console = Console()

    table = Table(show_header=True, header_style="bold", show_lines=True)
    table.add_column(jobconfig_data["display_name"], justify="center")
    table.add_row(jobconfig_data["long_description"])

    args_subtable = Table(show_header=True)
    table.add_row("Arguments", style="bold")
    if "args" in jobconfig_data.keys() and jobconfig_data["args"] is not None:
        args_subtable.add_column("Name")
        args_subtable.add_column("Description")
        args_subtable.add_column("Required")
        args_subtable.add_column("Options")

        for arg in jobconfig_data["args"]:
            args_subtable = _add_row_to_subtable(args_subtable, arg)
        table.add_row(Align.center(args_subtable))
    else:
        table.add_row("Good news! This job has no arguments")

    console.print(table)


def _add_row_to_subtable(subtable: Table, row: dict) -> Table:
    """
    Takes a Table representing the args subtable and returns a Table with the row added to it
    This function accounts for missing items so they're not printed as empty

    Args:
        subtable (Table): The Table representing the args subtable
        row (dict): A dictionary representing a single argument

    Returns:
        Table: The Table with the row added to it
    """
    options_string = " ".join(row["options"])

    if "description" not in row.keys():
        row["description"] = "N/A"

    subtable.add_row(
        row["name"], row["description"], str(row["required"]), options_string
    )
    return subtable
